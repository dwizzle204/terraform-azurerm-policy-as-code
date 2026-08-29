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

**Built-in definitions** (`source = "builtin"`): set `definition_id = "/providers/Microsoft.Authorization/policyDefinitions/<name>"`, optional `version` (exact `3.1.0` stays `3.1.0`, `3.1.*` stays wildcard, `null` = unversioned/latest). Pinned built-ins should supply `parameters`/`policy_rule`/`mode` only when remediation/mode-specific behavior is needed. Unpinned built-ins hydrate `mode`/`parameters`/`policy_rule`/`roleDefinitionIds` automatically via `data.azurerm_policy_definition_built_in`.

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
  source = "gettek/policy-as-code/azurerm//modules/intent"

  definitions = {
    deny_risky_ports = { category = "Network", policy_name = "network_security_group_deny_port_scanner" }
    allowed_locations_builtin = {
      source        = "builtin"
      definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
      # version = "3.1.0" # exact pin stays exact; omit for latest
    }
  }

  initiatives = {
    platform_baseline = {
      display_name           = "Platform Baseline"
      member_definition_keys = ["deny_risky_ports", "allowed_locations_builtin"]
    }
  }

  initiatives = {
    platform_baseline = {
      display_name           = "Platform Baseline"
      member_definition_keys = ["deny_risky_ports"]
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
