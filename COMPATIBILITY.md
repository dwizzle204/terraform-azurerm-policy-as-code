# Compatibility Matrix

Single source of truth for the Terraform and provider versions this repository
is validated against. All five modules (`definition`, `initiative`,
`exemption`, `def_assignment`, `set_assignment`) declare identical constraints.

| Component | Minimum | Tested | Notes |
|-----------|---------|--------|-------|
| Terraform | >= 1.11 | 1.15.9 | Floor exists for the offline `terraform test` / `mock_provider` suites run in CI (`override_during` requires >= 1.11) |
| azurerm   | >= 4.35, < 6.0 | 5.2.0 | `< 6.0` caps the next unvalidated major |
| azuread   | >= 2.0, < 4.0 | 3.x | Used by `def_assignment` / `set_assignment` group membership |
| random    | >= 3.1, < 4.0 | 3.9 | Used by `definition` replacement triggers |

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
