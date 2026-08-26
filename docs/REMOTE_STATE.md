# Remote State Architecture

Vendor-neutral guidance for operating these modules with centralized remote
state. No specific backend product is assumed.

## Why centralize

Policy objects are shared governance surfaces: several teams plan against the
same definitions/initiatives/assignments. Local state cannot provide locking,
shared visibility, or access control, and invites concurrent-write corruption.

## Reference architecture (one storage+locking service)

| Concern | Requirement | Typical implementation shape |
|---|---|---|
| Storage | Versioned object store, encrypted at rest | blob store + server-side encryption |
| Locking | Exclusive lease per state write | backend-native lock |
| Access control | Least privilege per state file | RBAC scoped to containers/prefixes |
| Audit | Every read/write logged and attributable | platform audit logs enabled |
| Backup | Point-in-time recovery of prior states | versioning + soft delete |

## Recommended state boundaries

Split states by change velocity and blast radius:

- **`policy-core`** — custom definitions, initiatives, assignments.
  Slow-moving; changes are governance decisions requiring review.
- **`policy-exemptions`** — governed exemptions. Higher-frequency
  (risk tickets expire/renew weekly) but individually low-risk.
- **optional `policy-remediation`** — explicit remediation execution, when
  separated from assignment creation to constrain who can trigger mass
  resource changes.

Trade-offs: more states mean more wiring (cross-state references via data
sources or resource IDs passed as variables) but smaller blast radius,
narrower RBAC per team, faster plans. Do not create one state per policy —
that inverts into unmanageable sprawl.

With this repository's modules, the split works naturally: exemptions take an
`policy_assignment_id` input, so the exemptions state only needs read access to IDs
produced by the core state (pass them as variables from pipeline output).

## Naming conventions

`<org>-<platform>-<boundary>-<env>` for state files, e.g.
`contoso-azure-policy-core-prod`. One workspace/state per environment boundary;
never share a state across environments.

## Backup / recovery / migration

- Enable versioning + soft-delete on the storage layer before first apply.
- Practice restoring a state copy into a scratch backend quarterly.
- Use `terraform state mv` / `-replace` for renames inside a state; use the
  documented import flow when adopting existing Azure Policy objects.
- Never hand-edit state except as a last resort with a fresh backup.

## Anti-patterns

- Monolithic state holding every policy object for every environment
- Credentials embedded in backend configuration (use workload identity /
  OIDC; see repo SECURITY posture — no secrets in code or logs)
- Unlocked local state for shared assignments
- Allowing broad `Contributor` on the state container instead of scoped roles
