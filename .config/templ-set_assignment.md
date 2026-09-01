# POLICY INITIATIVE ASSIGNMENT MODULE

Assignments can be scoped from overarching management groups right down to individual resources by settings the `assignment_scope`.

## Role Definitions & Assignments

A role assignment and remediation task will be automatically created if any member definition contains a list of `roleDefinitionIds`. This can be omitted with `skip_role_assignment=true`, or to assign roles at a different scope to that of the policy assignment use: `role_assignment_scope`.

For a cleaner solution, a list of `aad_group_remediation_object_ids` can be supplied for System Assigned Identity membership in favour of role assignments, assuming the appropriate RBAC controls already exist for that group. More info on role assignments can be found in the [main README](../../README.md#role-assignments)

## Assignment Effects

The `assignment_effect` parameter is useful when an initiative contains multiple effects of the same type and `merge_effects=true`, ensuring that all `member_definitions` are assigned with the same effect.

- Omit `assignment_effect` to use each definition's default effect stored in its policy parameters.
- Specify effects individually by setting them in `assignment_parameters` for more granular control.

## Override contract

The `overrides` input is a `policyEffect`-only abstraction. This module supports
AzureRM `>= 4.35`; AzureRM 4.43 (September 2025) introduced configurable
`override.kind` (including `policyVersion`), which is intentionally not exposed
here. Supporting `policyVersion` requires raising the provider floor to 4.43+.
If additional kinds
are supported in future, remediation effect calculation must ignore non-
`policyEffect` overrides and the provider compatibility floor will be reviewed.

## Examples

### Custom Policy Initiative Assignment with Not-Scope and Overrides (preview)

The optional `overrides` property allows you to change the effect of a member definition without modifying the underlying policy definition or using a parameterized effect in the policy definition.

> 📘 [Microsoft Docs: Azure Policy assignment structure (Overrides)](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/assignment-structure#overrides-preview)
> 💡 **Note:** This module also supports Resource selectors (preview), see the [`def_assignment`](../def_assignment) module for an example input

```hcl
module org_mg_configure_asc_initiative {
  source                 = "gettek/policy-as-code/azurerm//modules/set_assignment"
  initiative             = module.configure_asc_initiative.initiative
  assignment_scope       = data.azurerm_management_group.org.id
  assignment_effect      = "DeployIfNotExists"

  # resource remediation options
  skip_role_assignment   = false
  skip_remediation       = false
  re_evaluate_compliance = true

  assignment_parameters = {
    workspaceId           = local.dummy_resource_ids.azurerm_log_analytics_workspace
    eventHubDetails       = local.dummy_resource_ids.azurerm_eventhub_namespace_authorization_rule
    securityContactsEmail = "admin@cloud.com"
    securityContactsPhone = "44897654987"
  }

  assignment_not_scopes = [
    data.azurerm_management_group.team_a.id
  ]

  # use the 'non_compliance_messages' output from the initiative module to use auto generated messages based off policy properties: descriptions/display names/custom ones found in metadata
  # override with your own Key/Value pairs map as 'policy_definition_reference_id = content', use null = 'content' to specify the Default non-compliance message for all member definitions.
  non_compliance_messages = module.configure_asc_initiative.non_compliance_messages

  # optional overrides (preview)
  # optional overrides (preview): typed selector contract (#8)
  overrides = [
    {
      value = "AuditIfNotExists"
      selectors = [
        {
          kind = "policyDefinitionReferenceId"
          in   = [ "ExportAscAlertsAndRecommendationsToEventhub", "ExportAscAlertsAndRecommendationsToLogAnalytics" ]
        }
      ]
    },
    {
      value = "Disabled"
      selectors = [
        {
          kind = "policyDefinitionReferenceId"
          in   = [ "AutoSetContactDetails" ]
        }
      ]
    }
  ]
}
```

### Built-In Policy Initiative Assignment
```hcl
# Should use name instead of display name, as Microsoft changes the display names.
data "azurerm_policy_set_definition" "cis_1_3_0" {
  name = "612b5213-9160-4969-8578-1518bd2a000c" #"CIS Microsoft Azure Foundations Benchmark v1.3.0"
}

module org_mg_cis_1_3_0_benchmark {
  source           = "gettek/policy-as-code/azurerm//modules/set_assignment"
  initiative       = data.azurerm_policy_set_definition.cis_1_3_0
  assignment_scope = data.azurerm_management_group.org.id

  assignment_parameters = {
    "effect-b954148f-4c11-4c38-8221-be76711e194a-MicrosoftSql-servers-firewallRules-delete" = "Disabled"
  }
}
```

### Built-In Policy Initiative Containing DINE/Modify Assignment

```hcl
# Should use name instead of display name, as Microsoft changes the display names.
data "azurerm_policy_set_definition" "configure_az_monitor_linux_vm_initiative" {
  name = "118f04da-0375-44d1-84e3-0fd9e1849403" #"Configure Linux machines to run Azure Monitor Agent and associate them to a Data Collection Rule"
}

data "azurerm_role_definition" "vm_contributor" {
  name = "Virtual Machine Contributor"
}

module org_mg_configure_az_monitor_linux_vm_initiative {
  source           = "gettek/policy-as-code/azurerm//modules/set_assignment"
  initiative       = data.azurerm_policy_set_definition.configure_az_monitor_linux_vm_initiative
  assignment_scope = data.azurerm_management_group.org.id
  skip_remediation = false

  role_definition_ids = [
    data.azurerm_role_definition.vm_contributor.id
  ]

  assignment_parameters = {
    listOfLinuxImageIdToInclude = []
    dcrResourceId               = "/Data/Collection/Rule/Resource/Id"
  }
}
```
