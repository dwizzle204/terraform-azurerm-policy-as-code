# POLICY DEFINITION ASSIGNMENT MODULE

Assignments can be scoped from overarching management groups right down to individual resources by settings the `assignment_scope`.

## Role Definitions & Assignments

A role assignment and remediation task will be automatically created if the `policyRule` contains a list of `roleDefinitionIds`. This can be omitted with `skip_role_assignment=true`, or to assign roles at a different scope to that of the policy assignment use: `role_assignment_scope`.

For a cleaner solution, a list of `aad_group_remediation_object_ids` can be supplied for System Assigned Identity membership in favour of role assignments, assuming the appropriate RBAC controls already exist for that group. More info on role assignments can be found in the [main README](../../README.md#role-assignments)

## Override contract

The `overrides` input is a `policyEffect`-only abstraction. This module supports
AzureRM `>= 4.35`; AzureRM 4.43 (September 2025) introduced configurable
`override.kind` (including `policyVersion`), which is intentionally not exposed
here. Supporting `policyVersion` requires raising the provider floor to 4.43+.
If additional kinds
are supported in future, remediation effect calculation must ignore non-
`policyEffect` overrides and the provider compatibility floor will be reviewed.

This module assigns a **direct policy definition**, which has no initiative
member reference ids: `policyDefinitionReferenceId` override selectors are
initiative-scoped and are **rejected at plan time** here (use the
[`set_assignment`](../set_assignment) module for initiative assignments).
Supported selector contracts for `overrides`:

- **no selectors**: an unconditional global override
- `resourceLocation` (`in` only): applied when every selector's location set
  provably intersects the remediation task's `location_filters`; treated as
  resource-dependent (automatic remediation suppressed) when no proof is
  possible, and excluded entirely when provably disjoint

`resource_selectors` additionally support `resourceType` and
`resourceWithoutLocation`; the latter only accepts the value
`subscriptionLevelResources`.



**Conjunctive selectors:** Azure ANDs all selectors within one override, so an
override only applies when **every** selector is satisfied; a contradictory
selector pair (e.g. `in`/`not_in` for the same location set) never applies.
`policyDefinitionReferenceId` selectors are initiative-scoped and rejected for
direct definition assignments (#69).

**`resourceWithoutLocation` selectors** only support the value
`subscriptionLevelResources` (enforced at plan time).

## Examples

### Assign a definition with Modify effect to automatically create a role assignment and remediation task

```hcl
module team_a_mg_inherit_resource_group_tags_modify {
  source            = "gettek/policy-as-code/azurerm//modules/def_assignment"
  definition        = module.inherit_resource_group_tags_modify.definition
  assignment_scope  = data.azurerm_management_group.team_a.id
  assignment_effect = "Modify"
  skip_remediation  = var.skip_remediation

  assignment_parameters = {
    tagName = "environment"
  }
}
```

### Assign a definition with Modify effect to automatically create a role assignment and remediation task with an explicit role

```hcl
data azurerm_role_definition contributor {
  name = "Contributor"
}

module team_a_mg_inherit_resource_group_tags_modify {
  source            = "gettek/policy-as-code/azurerm//modules/def_assignment"
  definition        = module.inherit_resource_group_tags_modify.definition
  assignment_scope  = data.azurerm_management_group.team_a.id
  assignment_effect = "Modify"
  skip_remediation  = var.skip_remediation

  # specify a list of role definitions or omit to use those defined in the policies
  role_definition_ids = [
    data.azurerm_role_definition.contributor.id
  ]

  # specify a different role assignment scope or omit to use the policy assignment scope
  role_assignment_scope = data.azurerm_management_group.team_a.id

  assignment_parameters = {
    tagName = "environment"
  }
}
```

### Create a Built-In Policy Definition Assignment with Custom Non-Compliance Message

```hcl
# Should use name instead of display name, as Microsoft changes the display names.
data azurerm_policy_definition_built_in deploy_law_on_linux_vms {
  name =  "053d3325-282c-4e5c-b944-24faffd30d77" #"Deploy Log Analytics extension for Linux VMs"
}

module team_a_mg_deploy_law_on_linux_vms {
  source            = "gettek/policy-as-code/azurerm//modules/def_assignment"
  definition        = data.azurerm_policy_definition_built_in.deploy_law_on_linux_vms
  assignment_scope  = data.azurerm_management_group.team_a.id
  skip_remediation  = var.skip_remediation

  assignment_parameters = {
    logAnalytics           = local.dummy_resource_ids.azurerm_log_analytics_workspace
    listOfImageIdToInclude = [
      local.dummy_resource_ids.custom_linux_image_id
    ]
  }

  non_compliance_message = "Example non-compliance message will be used as opposed to default policy error"
}
```

### Assign a definition with Modify effect but add identity to an AAD Group instead of role-assignment

```hcl
data "azuread_group" "policy_remediation" {
  display_name     = "policy_remediation"
  security_enabled = true
}

module team_a_mg_inherit_resource_group_tags_modify {
  source               = "gettek/policy-as-code/azurerm//modules/def_assignment"
  definition           = module.inherit_resource_group_tags_modify.definition
  assignment_scope     = data.azurerm_management_group.team_a.id
  skip_remediation     = false
  skip_role_assignment = true # <- set this to true to avoid role assignments

  assignment_parameters = {
    tagName = "environment"
  }
}

resource "azuread_group_member" "remediate_team_a_mg_inherit_resource_group_tags_modify" {
  group_object_id  = data.azuread_group.policy_remediation.id
  member_object_id = module.team_a_mg_inherit_resource_group_tags_modify.principal_id
}
```

### Resource selectors (preview)

The optional `resource_selectors` property facilitates safe deployment practices (SDP) by enabling you to gradually roll out policy assignments based on factors like resource location, resource type, or whether a resource has a location.

> 📘 [Microsoft Docs: Azure Policy assignment structure (Resource selectors)](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/assignment-structure#resource-selectors-preview)

The example below demonstrates the acceptable format for this module:

```hcl
module "org_mg_whitelist_regions" {
  source            = "gettek/policy-as-code/azurerm//modules/def_assignment"
  definition        = module.whitelist_regions.definition
  assignment_scope  = data.azurerm_management_group.org.id
  assignment_effect = "Deny"

  assignment_parameters = {
    listOfRegionsAllowed = [ "uk", "uksouth", "ukwest", "europe", "northeurope", "westeurope", "global" ]
  }

  # optional resource selectors (preview)
  # optional resource selectors (preview): typed selector contract (#8)
  resource_selectors = [
    {
      name = "SDPRegions"
      selectors = [
        {
          kind = "resourceLocation"
          in   = [ "uk", "uksouth", "ukwest" ]
        }
      ]
    },
    {
      name = "SDPResourceTypes"
      selectors = [
        {
          kind = "resourceType"
          in   = [ "Microsoft.Storage/storageAccounts", "Microsoft.EventHub/namespaces", "Microsoft.OperationalInsights/workspaces" ]
        }
      ]
    }
  ]
}
```
