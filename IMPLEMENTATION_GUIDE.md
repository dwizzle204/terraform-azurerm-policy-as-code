# Implementation Guide

The paved path for a platform engineer who knows Terraform and Azure but has
never used this repository. Work through the sections in order; by the end you
will have implemented, tested, and promoted a real Azure Policy control plane
from a cold start.

> **New implementation?** Consume [`modules/intent`](modules/intent). Everything
> else is a lower-level framework primitive or escape hatch. A complete,
> tested walkthrough lives in [`examples/caf-landing-zone`](examples/caf-landing-zone).

---

## 1. What this framework is — and is not

**Is:**

- A Terraform-native control plane for **Azure Policy**: definitions,
  initiatives (policy sets), assignments, exemptions, and remediation tasks,
  with a data-driven orchestration layer ([`modules/intent`](modules/intent)).
- Azure-native in semantics. Everything this framework produces is a real Azure
  Policy ARM object; effects, inheritance, overrides, and exemptions behave
  exactly as Azure Policy documents them.

**Is not:**

- An EPAC rewrite in Terraform. EPAC manages policy as declarative
  JSON/data with its own deployment engine; this framework is plain Terraform
  with typed modules.
- A universal multi-cloud policy DSL. There is exactly one target: Azure Policy
  via the [`azurerm` provider](COMPATIBILITY.md).
- A production policy catalog. The bundled [`policies/`](policies) tree is
  **reference/example content** that the modules' tests use; see
  [Policy Catalog vs Framework](docs/POLICY_CATALOG.md). Your organization owns
  its own catalog.

---

## 2. Recommended entry point

Start with [`modules/intent`](modules/intent). You declare typed maps of
**intent** — definitions, initiatives, assignments, exemptions — and the module
composes the lower-level modules for you. You never select a scope-specific
AzureRM assignment resource (`azurerm_management_group_policy_assignment` vs
`azurerm_subscription_policy_assignment` vs …) yourself; intent picks the right
one from the scope's ARM shape.

The remaining modules are lower-level framework primitives and escape hatches:

| Module | Role |
|---|---|
| [`modules/definition`](modules/definition) | Creates a custom policy definition from a JSON file in your catalog |
| [`modules/initiative`](modules/initiative) | Groups custom + built-in definitions into a policy set |
| [`modules/def_assignment`](modules/def_assignment) | Assigns a single definition (rare; prefer an initiative) |
| [`modules/set_assignment`](modules/set_assignment) | Assigns an initiative |
| [`modules/exemption`](modules/exemption) | A single governed exemption |
| [`modules/intent`](modules/intent) | **The recommended consumer surface** |

Reach for the primitives when intent does not fit (for example, assignments
managed by a separate pipeline or a shared service), not by default.

---

## 3. Prerequisites and compatibility

| Component | Required | Notes |
|---|---|---|
| Terraform | `>= 1.11` | Floor exists for the offline `terraform test` / `mock_provider` suites ([COMPATIBILITY.md](COMPATIBILITY.md)) |
| azurerm   | `>= 4.35, < 6.0` | Provider for all Azure Policy resources |
| azuread   | `>= 2.47, < 4.0` | Only required when using AAD-group remediation membership; declared transitively via `modules/intent` |

**Azure permissions** the deployment principal needs:

- **Resource Policy Contributor** at both `definition_scope` and
  `assignment_scope` (create definitions, initiatives, assignments).
- **User Access Administrator** at the `definition_scope` (recommended) or
  `assignment_scope` — only when the framework must create role assignments
  for remediation identities.
- **Microsoft Graph application permissions** `Group.Read.All` and
  `GroupMember.ReadWrite.All` — only when using
  `aad_group_remediation_object_ids`.
- Exemption creation requires `Microsoft.Authorization/policyExemptions/write`
  at the exemption scope.

**Identity for the pipeline:** authenticate with OIDC / workload identity
federation. Do not put client secrets or certificates in code or state. The
framework itself contains no credentials. Mocked `terraform test` is
credential-free; a real `terraform plan` that hydrates unpinned built-ins
queries Azure via `data.azurerm_policy_definition_built_in` and requires an
authenticated AzureRM provider.

---

## 4. Reference repository layout

Two distinct things live here; keep them separate in your own repository too.

```text
your-repo/
├── policy-catalog/            # YOUR organization's policy JSON (framework's policies/ is only an example)
├── intent/                    # YOUR intent data: HCL maps or YAML decoded with yamldecode
│   ├── definitions.yaml
│   ├── initiatives.yaml
│   ├── assignments.yaml
│   └── exemptions.yaml
├── root.tf                    # your Terraform root consuming modules/intent
├── versions.tf
└── tests/                     # your credential-free terraform test suites
```

In this repository the same separation exists:

```text
modules/            # the maintained, tested framework (this is the product)
policies/           # reference/example policy content — not a production baseline
examples-intent/    # YAML-driven consumer example
examples/           # additional examples, including examples/caf-landing-zone
docs/               # governance & operations guides
modules/*/tests/    # per-module credential-free contract tests
```

See [Policy Catalog vs Framework](docs/POLICY_CATALOG.md) for why the bundled
catalog must not become your production baseline by inertia.

---

## 5. State and pipeline boundaries

Policy objects are shared governance surfaces — several teams plan against the
same definitions. Use centralized remote state with locking, RBAC, and audit.
Full vendor-neutral guidance: [docs/REMOTE_STATE.md](docs/REMOTE_STATE.md).

Split state by blast radius:

| State | Contents | Change velocity |
|---|---|---|
| `policy-core` | definitions, initiatives, assignments | slow; every change is a governance decision |
| `policy-exemptions` | governed exemptions | higher frequency, individually low risk |
| `policy-remediation` *(optional)* | explicit remediation execution | decouples task creation from task running |

Operating model for every change:

```text
pull request
  → credential-free offline tests (fmt, tflint, mocked terraform test)
  → terraform plan against the target state
  → human approval (governance review)
  → apply
```

Definition, assignment, and exemption state are governance decisions; keep
them out of application teams' pipelines.

---

## 6. First implementation walkthrough

The fastest way to a working implementation is to copy and adapt the CAF
landing-zone example: [`examples/caf-landing-zone`](examples/caf-landing-zone).
It assumes a CAF-style management-group hierarchy that **already exists**
(this framework does not create management groups):

```text
Tenant root
└── <organization root>
    ├── Platform
    ├── Landing zones
    └── Sandboxes
```

The walkthrough, which the example implements end to end:

1. **Definitions** — declare custom policy intent (or reference Microsoft
   built-ins) in the `definitions` map. Built-ins are referenced by id and
   optional pinned version; customs point at JSON files in your catalog.
2. **Initiatives** — group members into per-scope initiatives. Remember an
   initiative must be created in (or above) every scope it is assigned from —
   the example creates one initiative per management group scope.
3. **Management-group assignments** — one assignment intent per scope:
   - **Platform** — a DeployIfNotExists/Modify control with
     `remediate = true`, `remediate_effects`, and `role_definition_ids`, so the
     framework wires the managed identity, RBAC, and a remediation task.
   - **Landing zones** — the stricter workload guardrails (for example an
     allowed-locations Deny control) with assignment parameters and control
     metadata, `enforcement = true`.
   - **Sandboxes** — the same or similar baseline with the deliberate relaxed
     posture (`enforcement = false`, or Audit instead of Deny). Sandbox is
     still governed and still inherited; it is not an ungoverned escape hatch.
4. **Identity / RBAC / remediation** — handled by the assignment when the
   policy rule carries `roleDefinitionIds` and `remediate = true` (section 8).
5. **Governed exemption** — a temporary waiver at a child subscription under
   the Landing zones assignment, linked by the assignment's **logical key**
   (section 9).

Inheritance does the rest: assignments at Platform, Landing zones, and
Sandboxes flow down to every descendant subscription and resource unless an
exemption carves one out. Definitions should live high in the hierarchy;
assignments as low as the governance decision requires.

---

## 7. Built-in vs custom policy guidance

- **Prefer Microsoft built-ins** where a suitable policy exists: they are
  maintained by Microsoft, survive definition drift, and need no catalog.
  Reference them with `source = "builtin"`, `definition_id`, and (optionally) a
  pinned `version`.
- **Pin versions deliberately.** An unpinned built-in reference tracks Azure's
  current version; a pinned one (`version = "3.1.*"`) freezes the selector.
  Pin when a control must not move under you; otherwise leave unpinned.
- **Custom definitions are organization-owned content.** Keep their JSON in
  your catalog with review workflow, and let `modules/definition` create them
  deterministically (name is `prefix + 8-char schema hash`).
- **Catalog `metadata.version` is not Azure `definitionVersion`.** A
  `metadata.version` like `"1.0.0"` on a custom definition is your content
  version; it never becomes a policy reference version selector. Only built-in
  references take a `version` selector, and only when you set it explicitly.
  See the root [README](README.md#versioning-catalog-metadata-vs-azure-definitionversion-selectors).

---

## 8. Remediation behavior

- **Remediation is opt-in.** By default no remediation tasks are created.
  Set `remediate = true` on an intent assignment (or populate
  `remediate_effects` on a direct assignment).
- **DeployIfNotExists / Modify only.** `remediate_effects` defaults to
  `["DeployIfNotExists", "Modify"]`; Audit/Deny/Disabled members are never
  remediated.
- **Managed identity and RBAC are required.** The policy rule's
  `roleDefinitionIds` (or your explicit `role_definition_ids`) drive both the
  identity and the role assignments. Assignment-only deployments that skip
  remediation need no RBAC privileges at all.
- **`enforcement = false` (DoNotEnforce) does not block remediation.** Azure
  supports manual remediation of DeployIfNotExists assignments under
  DoNotEnforce; an explicitly requested remediation task is still created.
- **`remediation_reference_ids` is an escape hatch** for members whose effect
  cannot be resolved automatically (for example a pinned built-in without a
  hydrated rule). It selects those members explicitly; it cannot rescue
  members whose known effect is non-remediable.

---

## 9. Governed exemptions

Prefer an exemption over a permanent `not_scopes` entry whenever a waiver is
time-bound or ownership matters:

- `not_scopes` is a silent, undated exclusion baked into the assignment —
  easy to forget, hard to audit.
- An exemption carries **owner, tracking reference, reason, expiry**, and
  optional approver/mitigation, and Azure removes it automatically at expiry.

In the intent interface, link an exemption to an assignment by **logical key**
and scope it at the narrowest surface that needs relief (typically a child
subscription under a management-group assignment):

```hcl
exemptions = {
  lz_sub_allow_http = {
    assignment_key = "landing_zones"          # logical key of the assignment
    scope          = var.landing_zone_subscription_id
    name           = "Temporary legacy HTTP endpoint"
    display_name   = "Waiver: legacy HTTP endpoint during migration"
    description    = "Tracking AZ-1042; removed at migration completion"
    category       = "Waiver"
    expires_on     = "2026-12-31"
    governed = {
      owner              = "workload-team"
      tracking_reference = "AZ-1042"
      reason             = "Legacy endpoint pending TLS migration"
      approver           = "platform-team"
    }
  }
}
```

Governed fields are validated (expiry required, must be in the future for
waivers) — see the [governance integration guide](docs/GOVERNANCE_INTEGRATION.md).

---

## 10. Testing and promotion

The normal PR path is **credential-free**:

- `terraform fmt -check -recursive`
- `tflint --recursive`
- per-module `terraform test` with **mocked providers** — proves module
  contracts, effect resolution, selector semantics, and remediation selection
  without an Azure tenant
- example-root validations and expected-failure negative checks

Run everything locally with `./scripts/test.sh`; details in
[TESTING.md](TESTING.md).

**Live Azure acceptance is a separate production-promotion gate.** The mocked
suite cannot prove ARM acceptance, identity/RBAC propagation timing, or actual
remediation task execution. Before promoting a new policy baseline to
production, run the opt-in live suite ([`integration-tests/azure`](integration-tests/azure/README.md))
against a disposable scope. Promotion checklist: offline gates green → plan
reviewed → live acceptance passed → approved apply.

---

## 11. Supported and intentionally unsupported behavior

**Supported:**

- Definitions, initiatives, assignments, exemptions, and remediation at
  management group, subscription, resource group, and resource scopes — the
  correct AzureRM resource is selected automatically from the scope shape.
- Effect-filtered, opt-in remediation including under DoNotEnforce.
- `policyEffect` overrides and resource selectors (typed contracts, AND
  semantics, resource-location overrides treated conservatively for
  remediation).
- Governed exemptions with ownership, tracking, and expiry validation.
- Built-in references with optional pinned Azure `definitionVersion` selectors.

**Intentionally unsupported (by design):**

- **Management-group hierarchy provisioning.** The framework assigns to your
  existing hierarchy; it never creates management groups.
- **Custom Azure Policy Definition Version resources.** Setting
  `metadata.version` on a custom definition does not create or resolve an
  Azure policy-definition version; only built-in references take explicit
  version selectors.
- **Non-`policyEffect` override kinds** (for example `policyVersion`).
  The `overrides` contract is `policyEffect`-only at the current provider
  floor (`azurerm >= 4.35`); AzureRM 4.43's configurable `override.kind` is
  deliberately not exposed until the floor is raised.
- **A universal policy DSL or multi-cloud targets.** Azure Policy only.

If you need one of these, model it explicitly in your own repository rather
than expecting the framework to infer it.

---

## Related documentation

- [COMPATIBILITY.md](COMPATIBILITY.md) — supported Terraform/provider matrix
- [Policy Catalog vs Framework](docs/POLICY_CATALOG.md)
- [Remote State Architecture](docs/REMOTE_STATE.md)
- [Governance Control Catalog Integration](docs/GOVERNANCE_INTEGRATION.md)
- [TESTING.md](TESTING.md) — test strategy and how to run it
- [CAF landing-zone example](examples/caf-landing-zone) — the walkthrough implementation
