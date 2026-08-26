# Governance Control Catalog Integration

How to connect an external governance control catalog (GRC tool, compliance
framework, spreadsheet — any system of record) to the Azure Policy artifacts
managed by these modules.

## Principle

One governance operating model, platform-native enforcement adapters. The
catalog owns **stable control identifiers and workflow metadata**; Azure
Policy remains the enforcement implementation with its own native semantics.
Do not invent a universal policy DSL on top — it hides Azure capabilities that
matter (effects, parameters, resource selectors, remediation behavior).

## Metadata pattern

Every module exposes a free-form metadata input — `policy_metadata`
(definition), `initiative_metadata` (initiative), `assignment_metadata`
(set_assignment/def_assignment), and `metadata` (exemption). Render catalog
fields into it consistently:

```hcl
module "initiative" {
  source = "../../modules/initiative"
  # ...
  initiative_metadata = {
    controlIds   = ["AC-01", "AC-02"]     # stable IDs from the catalog
    owner        = "platform-team"
    risk         = "high"
    environment  = "prod"
    ticketRef    = "GOV-2026-0141"
    approver     = "ciso-office"
    exceptionOf  = null                    # set when a control is waived
  }
}
```

Exemptions carry the same workflow fields through the governed contract
(`owner`, `requester`, `approver`, `tracking_reference`, `reason`,
`mitigation`) — see `modules/exemption/README.md`.

### Common vs cloud-specific

| Belongs in the catalog / metadata | Belongs in Azure-native config |
|---|---|
| control ID, owner, risk class | effect, parameters |
| environment, enforcement stage | resource selectors, overrides |
| exception status, approver, expiration | remediation task configuration |
| tracking/evidence references | definition bodies, policy versions |

## Example mapping

| Catalog control | Azure artifact | Where recorded |
|---|---|---|
| AC-01 Storage encryption | Built-in initiative reference | assignment parameter values + metadata.controlIds |
| AC-07 Legacy OS waiver | Custom exemption `EXC-10294` | exemption `governed.tracking_reference` |
| AC-12 Diagnostic logging | Custom definition from your catalog repo | definition `metadata.controlIds` |

The catalog remains authoritative for *why* something exists; this repository's
state remains authoritative for *what is deployed*. Reconciliation is a read of
deployed metadata versus catalog expectations — implementable as a CI check
that fails PRs whose assignments lack required control IDs.

## Data-driven maintenance

Pair with the [intent interface](../modules/intent/README.md): decode a
YAML/JSON export of your catalog at the root and feed assignments/exemptions
from it. Exemption renewals then arrive as PRs against the data file, with the
catalog as review context.
