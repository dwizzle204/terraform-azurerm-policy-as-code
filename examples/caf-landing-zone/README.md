# CAF Landing Zone reference implementation

A real, runnable [`modules/intent`](../../modules/intent) implementation that shows how
one policy framework expresses **three different governance intents** across the
Cloud Adoption Framework (CAF) management-group model.

> **New here?** Start with [`IMPLEMENTATION_GUIDE.md`](../../IMPLEMENTATION_GUIDE.md),
> then come back and copy this example.

## Assumed hierarchy

```text
Tenant Root
└── <Organization>                        (intermediate root)
    ├── Platform                          shared platform services
    ├── Landing zones                     workload guardrails
    └── Sandboxes                         permissive experimentation (still governed)
```

This example **does not provision management groups**. It assumes the hierarchy
already exists and only assigns policy against it. Management-group creation and
subscription placement belong to your landing-zone (e.g. CAF/ALZ) tooling — see
[Microsoft CAF: resource organization & management groups](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/resource-org-management-groups)
and [Microsoft ALZ](https://learn.microsoft.com/en-us/azure/architecture/landing-zones/).

Workload subscriptions sit **under** Landing zones (or Sandboxes) and inherit every
policy assignment made at those management groups automatically.

## What gets deployed

| Management group | Initiative | Control | Effect | Enforcement | Remediation |
| ---------------- | ---------- | ------- | ------ | ----------- | ----------- |
| Platform | `platform_baseline` | Deploy Network Watcher on new VNets (built-in, DINE) | `DeployIfNotExists` | enforced | **yes** — managed identity + RBAC + remediation task |
| Landing zones | `landing_zones_guardrails` | Allowed locations (built-in) | `Deny` | enforced | n/a |
| Sandboxes | `sandboxes_baseline` | Allowed locations (built-in) | `Deny` | **DoNotEnforce** | n/a |

Why each management group is different:

* **Platform** — the platform team owns shared services end to end, so a
  `DeployIfNotExists` control with a managed identity, role assignments and an
  explicit remediation task is appropriate. Remediation is opt-in
  (`remediate = true`); the framework resolves the identity and RBAC from the
  hydrated built-in policy rule.
* **Landing zones** — application workloads get the stricter guardrail baseline.
  `Deny` **enforced** means non-compliant requests are blocked at request time.
* **Sandboxes** — experimentation stays possible: the *same* location control runs
  under **DoNotEnforce**, so violations appear in compliance data without blocking
  requests. Sandboxes are still governed and still report compliance — this is an
  observe-first posture, not an ungoverned escape hatch.

Both Landing zones and Sandboxes constrain `listOfAllowedLocations` to
`westeurope`/`northeurope` via assignment parameters, and carry stable governance
metadata (`controlIds`, `owner`, `stage`) so external catalogs can reference these
controls.

## Governed exemption (child-scope waiver)

`landing_zones` is assigned at the Landing zones management group, but the example
waives it for **one workload subscription** (`landing_zone_subscription_id`).

```text
Landing zones MG  ── assignment: landing-zones-guardrails (Deny, enforced)
└── subscription  ── exemption: lz-waiver-data-residency-migration (future expiry)
```

The exemption is linked by the assignment's **logical key** (`assignment_key`),
scoped to the child subscription, and is *governed*: owner, tracking reference
(`ARCH-1234`), reason, approver, mitigation and a hard expiry.

This is preferable to adding a broad `not_scopes` entry to the assignment:

* it expires automatically instead of living forever in the assignment body
* it carries ownership and a tracking reference for audit
* the assignment body stays clean; waivers are managed as first-class records

## Files

```text
examples/caf-landing-zone/
├── README.md                  this file
├── versions.tf                provider pinning (no backend)
├── variables.tf               the four full ARM IDs this example needs
├── main.tf                    one modules/intent root: 3 initiatives, 3 assignments, 1 exemption
├── outputs.tf                 stable logical outputs
├── terraform.tfvars.example   copy to terraform.tfvars and fill in your IDs
└── tests/
    └── caf_landing_zone.tftest.hcl   credential-free mocked tests (same model as modules/*/tests)
```

## Run it

```bash
cd examples/caf-landing-zone
cp terraform.tfvars.example terraform.tfvars   # then edit the four IDs
terraform init -backend=false
terraform plan
```

Credential-free contract tests (no Azure access required):

```bash
terraform test
```

The tests use Terraform's mocked providers (`mock_provider "azurerm"`) — the same
offline strategy the module suites use — to prove the three scopes, the
enforcement contrast, the Platform remediation path and the exemption linkage.

## From example to production

* **Remote state** — wire a real backend following [`docs/REMOTE_STATE.md`](../../docs/REMOTE_STATE.md);
  consider separate state for policy core vs exemptions (see the guide's state
  and pipeline boundaries section).
* **Pin the built-ins** — this example deliberately uses unpinned built-ins so the
  current Microsoft rule content (including `roleDefinitionIds`) is hydrated. Pin
  versions deliberately when your change process requires it.
* **Replace placeholder control metadata** with your real governance catalog IDs.
* **Update the waiver expiry** and run the live Azure acceptance suite
  (`integration-tests/azure`) before promoting: mocked tests prove contracts, live
  tests prove ARM acceptance, identity/RBAC propagation and real remediation.
* **Pinning this framework** — this tested example uses the local module source
  (`../../modules/intent`). External consumers should pin this repository by git
  ref; do not substitute the upstream registry module, which does not contain
  these semantics (see [`IMPLEMENTATION_GUIDE.md`](../../IMPLEMENTATION_GUIDE.md)).
