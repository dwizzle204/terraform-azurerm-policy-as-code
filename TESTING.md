# Testing Strategy

This repository follows a layered test strategy (issue #16) so that **normal
PR validation requires no Azure tenant or credentials**. Only explicitly
opt-in integration tests touch live Azure.

## Layers

| Layer | Command | Requires Azure? | Proves |
|-------|---------|-----------------|--------|
| Static analysis | `terraform fmt -check -recursive` | No | Canonical formatting |
| Module validation | `terraform init -backend=false && terraform validate` | No | Configuration/provider schema validity |
| Offline contract tests | `terraform test` (per module, mocked providers) | No | Module logic: scope parsing, naming, parameter merging, remediation/identity selection, exemptions, initiative references |
| Negative validation | `scripts/test.sh` scratch plan | No | Missing policy definition files fail with a clear file error |
| Live integration | `terraform test` in `integration-tests/azure/` | **Yes** (disposable subscription) | ARM API acceptance, identity/RBAC propagation, real remediation |

## Quick start

```bash
./scripts/test.sh
```

Runs every offline layer and prints `ALL OFFLINE GATES PASSED` on success.
Requires Terraform >= 1.7 (`mock_provider`; developed against ~1.15).

## What the offline tests cover

Test files live next to their modules (`modules/<module>/tests/*.tftest.hcl`)
and use `mock_provider "azurerm"` / `"azuread"`:

- **initiative** — member parameter merging/suffixing, reference generation
  (plain + camel case + duplicate indexing), role definition collection,
  non-compliance message generation
- **definition** — `file_path` loading via fixture, runtime override
  precedence (documented quirk: file `metadata.version` wins over
  `var.policy_version`), library path resolution against the repo policies
  folder
- **set_assignment** — scope-to-resource selection (MG/sub/RG), assignment
  name trimming to 24 chars at MG scope, identity gating of remediation
  tasks, `skip_remediation`, effect merge into parameters
- **def_assignment** — scope selection, name trimming, explicit vs
  policy-rule role definition handling, remediation on/off, effect merge
- **exemption** — scope-to-resource selection, default category, expiry date
  normalization, camel case reference conversion, metadata encoding

### Known limitations

- `terraform test` cannot assert *expected* plan-time errors (a failing
  function call aborts the run rather than failing an assertion). The
  missing-definition-file case is therefore covered by an expected-failure
  scratch plan inside `scripts/test.sh`.
- Mocked tests cannot prove ARM-side acceptance; that is what
  `integration-tests/azure/` is for.

## Bug fixes surfaced by this strategy

Writing these tests exposed and fixed two real defects:

1. `set_assignment.remediation_tasks` output used a `try()` chain over
   `for_each` resource maps — maps never error when empty, so the output
   always returned the (empty) management-group map below MG scope. Now
   merged across all scopes.
2. `def_assignment` silently dropped explicit `role_definition_ids`
   (and therefore identity/RBAC/remediation) when the definition's
   `policy_rule` had no `then.details` block, because function arguments
   evaluate eagerly inside `coalescelist`. The role lookup is now null-safe.
3. `modules/definition` swallowed missing policy files with a `"{}"`
   fallback producing confusing downstream type errors — restored upstream's
   intended fail-loudly behavior (see gettek/terraform-azurerm-policy-as-code#11).

## CI mapping

| Workflow | Trigger | Credentials | Purpose |
|----------|---------|-------------|---------|
| `tests.yml` | PRs + pushes to main | none | fmt, validate, offline module tests |
| `ci.yml` | pushes to main only | deployment secrets | live Terraform plan/comment against the `examples` root |
| `cd.yml`, `cd-guest-config.yml` | manual/main | deployment secrets | deployments |

## Live integration suite

See [`integration-tests/azure/README.md`](integration-tests/azure/README.md).
Use a disposable subscription only; never run it against shared resources.
