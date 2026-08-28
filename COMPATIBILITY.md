# Compatibility Matrix

Single source of truth for the Terraform and provider versions this repository
is validated against. All six modules (`definition`, `initiative`, `exemption`, `def_assignment`, `set_assignment`, `intent`) declare identical constraints.

| Component | Minimum | Tested | Notes |
|-----------|---------|--------|-------|
| Terraform | >= 1.11 | 1.15.9 | Floor exists for the offline `terraform test` / `mock_provider` suites run in CI (`override_during` requires >= 1.11) |
| azurerm   | >= 4.35, < 6.0 | 5.2.0 | `< 6.0` caps the next unvalidated major |
| azuread   | >= 2.0, < 4.0 | 3.x | Used by `def_assignment` / `set_assignment` group membership |

CI runs the offline module suite against two Terraform lines (`~1.11`, `~1.15`)
and resolves the latest in-range provider versions, so both the floors and the
open upper bounds are exercised.

## Upgrade guidance

- **Pin deliberately as a consumer.** In root configurations prefer
  pessimistic constraints matching this matrix (e.g. `~> 5.2` for azurerm)
  rather than open lower bounds that can silently resolve a new major.
- **Upgrade deliberately, not accidentally.** When a new provider major
  releases, update your pin, read the provider changelog, run your plan, and
  only then widen module ranges here if validation passes.
- **Release notes call out constraint changes.** Any change to this matrix is
  a compatibility-relevant change and will be identified in release notes.

## Module floor rationale

- `>= 1.11`: oldest maintained Terraform line the offline test suite is
  validated against (`mock_provider` requires >= 1.7; `override_during`
  requires >= 1.11).
- azurerm `>= 4.35`: required by `initiative` member-definition versioning;
  all modules share one floor so mixed-module consumption cannot resolve an
  unsupported combination.

> Note: the `random` provider is no longer required by any module as of the deterministic definition naming change (#6).

## Remaining `any` inputs (deliberate)

| Module | Variable | Reason |
|--------|----------|--------|
| definition | `policy_metadata`, `policy_parameters`, `policy_rule` | Azure Policy's own JSON schema is external and large; top-level shape is validated (string or object) |
| initiative | `initiative_metadata` | free-form Azure metadata, shape validated |
| set_assignment / def_assignment | `assignment_parameters` | values are defined by each policy's own parameter schema |
| set_assignment / def_assignment | `assignment_metadata` | free-form Azure metadata |
| exemption | `metadata` | free-form Azure metadata, shape validated |


### #8 overrides / resource_selectors typed contracts

Rejected at plan time: map-form `selectors`, `effect` as the override payload key, missing
`kind` on resource selectors, >10 entries per input. See module README "Migration notes (#8)"
sections for before/after snippets.
