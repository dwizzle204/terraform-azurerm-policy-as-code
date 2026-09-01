# Intent Module

Higher-level, data-driven consumer interface (#13). Turns small typed maps of
*intent* into definitions → initiatives → assignments → exemptions using the
existing modules via `for_each`. Consumers never choose between the four
scope-specific AzureRM assignment resources; logical keys are stable and
deterministic. No new resource types — state lives in the underlying modules.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| definitions | map(key -> {`file_path` **or** `category+policy_name` **or** `source="builtin"` with `definition_id`}) | `map(object)` | `{}` | no |
| initiatives | map(key -> {display_name, member_definition_keys, ...}) | `map(object)` | `{}` | no |
| assignments | map(key -> {initiative_key, scope, ...}) | `map(object)` | `{}` | no |
| exemptions | map(key -> {assignment_key, scope, name, ..., governed?}) | `map(object)` | `{}` | no |

### Assignment fields

Each entry in `assignments` supports:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `initiative_key` | `string` | (required) | Logical key of the initiative to assign (must exist in `initiatives`). |
| `scope` | `string` | (required) | Full ARM id: management group, subscription, resource group or resource. The correct AzureRM assignment resource is selected automatically. |
| `assignment_name` | `string` | logical key | Physical assignment name. Collision-resistant naming is always enabled; a deterministic hash suffix prevents long keys colliding at MG scope. |
| `enforcement` | `bool` | `true` | Assignment enforcement mode. `false` = `DoNotEnforce` (request-time evaluation is not enforced). Does **not** block explicitly requested remediation. |
| `effect` | `string` | per-definition | Assignment-level effect override. Only valid when the initiative declares an `effect` parameter that the member's rule actually consumes; otherwise use `assignment_parameters`. |
| `parameters` | `any` | `{}` | Assignment parameter values keyed by initiative parameter name. Unknown keys fail fast at plan time. |
| `assignment_location` | `string` | `westeurope` | Azure region for the assignment/remediation identity resources (only relevant when identity is created). |
| `not_scopes` | `list(string)` | `[]` | ARM ids excluded from the assignment. Prefer a governed `exemptions` entry for time-bound exceptions. |
| `remediate` | `bool` | `false` | Opt in to remediation task creation for remediable members. |
| `remediate_effects` | `list(string)` | `["DeployIfNotExists", "Modify"]` | Effects eligible for automatic remediation selection. |
| `remediation_reference_ids` | `list(string)` | `[]` | Explicit member reference ids to remediate, bypassing effect resolution for unresolved-effect members (e.g. pinned built-ins without hydrated policy rules). |
| `role_definition_ids` | `list(string)` | `[]` | Explicit role definitions granted to the assignment's managed identity. Omit to use roles discovered from member policy rules. |
| `metadata` | `any` | `null` | Free-form metadata (e.g. `controlIds`, `owner`, `stage`) stored on the assignment. |

### Exemption fields

Each entry in `exemptions` supports:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `assignment_key` | `string` | (required) | Logical key of the assignment to exempt (must exist in `assignments`). |
| `scope` | `string` | (required) | ARM id being exempted (subscription, resource group or resource) — usually below the assignment's scope. |
| `name` | `string` | (required) | Physical exemption name. |
| `display_name` | `string` | (required) | Human-readable exemption title. |
| `description` | `string` | (required) | Why the exemption exists. |
| `category` | `string` | `Waiver` | Exemption category (`Waiver`, `Mitigated`, `Enforced`). Governed `Waiver`/`Mitigated` entries have extra requirements (expiry, mitigation). |
| `expires_on` | `string` | `null` | Expiry date (`YYYY-MM-DD`). Required for governed waivers; must be in the future. |
| `policy_reference_ids` | `list(string)` | `[]` | Restrict the exemption to specific member reference ids; empty exempts the whole assignment. |
| `metadata` | `any` | `null` | Free-form metadata passthrough. |
| `governed.owner` | `string` | (required if governed) | Team accountable for removing the waiver. |
| `governed.tracking_reference` | `string` | (required if governed) | Ticket/reference linking the waiver to work tracking. |
| `governed.reason` | `string` | (required if governed) | Why the exception is needed. |
| `governed.requester` / `approver` / `mitigation` / `governed_created_on` | `string` | `null` | Optional governance enrichment. |

Prefer a governed, expiring exemption over a broad or permanent `not_scopes`
entry: the exemption is scoped to one assignment, carries ownership/expiry
accountability, and fails fast when required governance attributes are missing
or stale.

**Built-in definitions** (`source = "builtin"`): set `definition_id = "/providers/Microsoft.Authorization/policyDefinitions/<name>"`, optional `version` (exact `3.1` stays `3.1`, `3.1.*` stays wildcard, `null` = unversioned/latest). Pinned built-ins should supply `parameters`/`policy_rule`/`mode` only when remediation/mode-specific behavior is needed. Unpinned built-ins hydrate `mode`/`parameters`/`policy_rule`/`roleDefinitionIds` automatically via `data.azurerm_policy_definition_built_in`.

Dangling references (unknown member/initiative/assignment keys) fail at plan
time with a diagnostic naming every offender.

Intent-created assignments always enable collision-resistant naming. Their
physical names include a deterministic hash suffix, preventing long logical
keys from colliding at management-group scope. Direct assignment modules retain
their legacy `collision_resistant_naming = false` default for compatibility.

## Outputs

| Name | Description |
|------|-------------|
| definition_ids | map key -> definition id |
| initiative_ids | map key -> initiative id |
| assignment_ids | map key -> assignment id |
| assignment_principal_ids | map key -> managed identity principal id |
| exemption_ids | map key -> exemption id |

## Example (custom + built-in)

```hcl
module "policy_intent" {
  # in-repo consumers use a relative source; external consumers should pin a
  # git tag/ref of THIS repository (dwizzle204/terraform-azurerm-policy-as-code),
  # NOT the upstream Registry module, which has materially different behavior:
  #   source = "git::https://github.com/dwizzle204/terraform-azurerm-policy-as-code.git//modules/intent?ref=<release-tag>"
  source = "../../modules/intent"

  definitions = {
    deny_risky_ports = { category = "Network", policy_name = "network_security_group_deny_port_scanner" }
    allowed_locations_builtin = {
      source        = "builtin"
      definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      # version = "3.1" # provider-valid pin (major.minor); 3.1.* for minor wildcard; 1.0.*-preview for preview
    }
  }

  initiatives = {
    platform_baseline = {
      display_name           = "Platform Baseline"
      member_definition_keys = ["deny_risky_ports", "allowed_locations_builtin"]
    }
  }

  assignments = {
    platform = {
      initiative_key = "platform_baseline"
      scope          = "/providers/Microsoft.Management/managementGroups/platform"
      effect         = "Deny"
    }
    sandbox = {
      initiative_key = "platform_baseline"
      scope          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sandbox-rg"
      enforcement    = false
    }
  }

  exemptions = {
    legacy_app = {
      assignment_key = "platform"
      scope          = "/subscriptions/00000000-0000-0000-0000-000000000000"
      name           = "legacy-app-waiver"
      display_name   = "Legacy App Waiver"
      description    = "Temporary waiver pending decommission"
      expires_on     = "2026-12-31"
      governed = {
        owner              = "app-team"
        tracking_reference = "RISK-2914"
        reason             = "Legacy dependency incompatible with control"
      }
    }
  }
}
```

## YAML / JSON driven usage

The intent maps are plain HCL values, so they can be decoded from YAML or JSON
at the root level without adding a provider dependency:

```hcl
locals {
  assignment_intents = yamldecode(file("assignments.yaml"))
}

module "policy_intent" {
  source      = "../../modules/intent"
  assignments = local.assignment_intents
}
```

See `examples-intent/` for a runnable root example.
