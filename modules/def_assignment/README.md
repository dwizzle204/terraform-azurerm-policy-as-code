<!-- BEGIN_TF_DOCS -->
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

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.4 |
| azurerm | >= 4.12 |



## Resources

| Name | Type |
|------|------|
| [azuread_group_member.remediation](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/group_member) | resource |
| [azurerm_management_group_policy_assignment.def](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_management_group_policy_remediation.rem](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_remediation) | resource |
| [azurerm_resource_group_policy_assignment.def](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_assignment) | resource |
| [azurerm_resource_group_policy_remediation.rem](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_remediation) | resource |
| [azurerm_resource_policy_assignment.def](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_policy_assignment) | resource |
| [azurerm_resource_policy_remediation.rem](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_policy_remediation) | resource |
| [azurerm_role_assignment.remediation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_subscription_policy_assignment.def](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_assignment) | resource |
| [azurerm_subscription_policy_remediation.rem](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_remediation) | resource |
| [terraform_data.def_assign_replace_def](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.def_assign_replace_param](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aad_group_remediation_object_ids | List of Azure AD Group Object Ids for the System Assigned Identity to be a member of. Omit this to use role_assignments | `list(string)` | `[]` | no |
| assignment_description | A description to use for the Policy Assignment, defaults to definition description. Changing this forces a new resource to be created | `string` | `null` | no |
| assignment_display_name | The policy assignment display name, defaults to definition display_name. Changing this forces a new resource to be created | `string` | `null` | no |
| assignment_effect | The effect of the policy. Changing this forces a new resource to be created | `string` | `null` | no |
| assignment_enforcement_mode | Control whether the assignment is enforced | `bool` | `true` | no |
| assignment_location | The Azure location where this policy assignment should exist, required when an Identity is assigned. Defaults to UK South. Changing this forces a new resource to be created | `string` | `"westeurope"` | no |
| assignment_metadata | The optional metadata for the policy assignment. | `any` | `null` | no |
| assignment_name | The name which should be used for this Policy Assignment, defaults to definition name. Changing this forces a new Policy Assignment to be created | `string` | `null` | no |
| assignment_not_scopes | A list of the Policy Assignment's excluded scopes. Must be full resource IDs | `list(string)` | `[]` | no |
| assignment_parameters | The policy assignment parameters. Changing this forces a new resource to be created | `any` | `{}` | no |
| assignment_scope | The scope at which the policy will be assigned. Must be full resource IDs. Changing this forces a new resource to be created | `string` | n/a | yes |
| definition | Policy Definition resource node | `any` | n/a | yes |
| failure_percentage | (Optional) A number between 0.0 to 1.0 representing the percentage failure threshold. The remediation will fail if the percentage of failed remediation operations (i.e. failed deployments) exceeds this threshold. | `number` | `null` | no |
| identity_ids | Optional list of User Managed Identity IDs which should be assigned to the Policy Definition | `list(string)` | `null` | no |
| location_filters | Optional list of the resource locations that will be remediated | `list(string)` | `[]` | no |
| non_compliance_message | The optional non-compliance message text. | `string` | `null` | no |
| parallel_deployments | (Optional) Determines how many resources to remediate at any given time. Can be used to increase or reduce the pace of the remediation. If not provided, the default parallel deployments value is used. | `number` | `null` | no |
| re_evaluate_compliance | Sets the remediation task resource_discovery_mode for policies that DeployIfNotExists and Modify. false = 'ExistingNonCompliant' and true = 'ReEvaluateCompliance'. Defaults to false. Applies at subscription scope and below | `bool` | `false` | no |
| remediation_scope | The scope at which the remediation tasks will be created. Must be full resource IDs. Defaults to the policy assignment scope. Changing this forces a new resource to be created | `string` | `null` | no |
| resource_count | (Optional) Determines the max number of resources that can be remediated by the remediation job. If not provided, the default resource count is used. | `number` | `null` | no |
| resource_selectors | Optional list of Resource selectors (preview), max 10. These facilitate safe deployment practices (SDP) by enabling you to gradually roll out policy assignments based on factors like resource location, resource type, or whether a resource has a location | `list(any)` | `[]` | no |
| role_assignment_scope | The scope at which role definition(s) will be assigned, defaults to Policy Assignment Scope. Must be full resource IDs. Ignored when using Managed Identities. Changing this forces a new resource to be created | `string` | `null` | no |
| role_definition_ids | List of Role definition ID's for the System Assigned Identity, defaults to roles included in the definition. Ignored when using Managed Identities. Changing this forces a new resource to be created | `list(string)` | `[]` | no |
| skip_remediation | Should the module skip creation of a remediation task for policies that DeployIfNotExists and Modify | `bool` | `false` | no |
| skip_role_assignment | Should the module skip creation of role assignment for policies that DeployIfNotExists and Modify | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The Policy Assignment Id |
| identity_id | The Managed Identity block containing Principal Id & Tenant Id of this Policy Assignment if type is SystemAssigned |
| remediation_id | The Id of the remediation task |
| role_definition_ids | The List of Role Definition Ids assignable to the managed identity |
<!-- END_TF_DOCS -->

## Collision-resistant assignment names (#2)

Set `collision_resistant_naming = true` to append a deterministic 8-character hash of (assignment scope, member definition identity, requested name) to the assignment name, preventing collisions between distinct logical assignments whose names share a long prefix. Management-group assignments remain within the 24-character Azure limit. Defaults to `false`; enabling it renames existing assignments and forces replacement.

## Migration notes

Enabling `collision_resistant_naming` changes the computed assignment name, forcing destroy/create replacement of existing assignments. Plan during a maintenance window.

## Remediation lifecycle (#1, #3)

Remediation is **opt-in and effect-aware**: the effective effect is the
`assignment_effect` override or the policy rule's `then.effect`, matched against
`remediate_effects` (default `[]` = disabled). `remediation_reference_ids`
explicitly selects this definition by name when the resolved effect is unresolved (empty). Known non-remediable effects remain rejected even when explicitly listed. An
`overrides` entry carrying a `resourceLocation` selector — alone or mixed with a
`policyDefinitionReferenceId` selector — makes the effective effect
resource-dependent: automatic remediation is suppressed unless `location_filters`
prove the override cannot apply to the remediated resources. An override with no
selectors at all is an unconditional global override and its value is used as-is.
Module-managed
role assignments now run before remediation tasks (`depends_on`). See
`modules/set_assignment/README.md` for the privilege table and externally
managed identity/RBAC patterns. Migration: set
`remediate_effects = ["DeployIfNotExists", "Modify"]` to approximate pre-#1
behavior.

## Remediation tasks & initiatives

Azure Policy processes **one policy definition reference per remediation
task**. When assigning an initiative, this module creates one remediation task
per eligible member definition reference (effect-filtered, see
`remediate_effects` / `remediation_reference_ids`), not a single task for the
whole initiative. Tasks are created only after the assignment's managed
identity role assignments have been established.


## Migration notes (#8)

`overrides` and `resource_selectors` are now typed lists of objects. The legacy
map-shaped forms **fail plan-time variable validation**:

```hcl
# BEFORE (rejected): effect key + single map selector
overrides = [
  {
    effect    = "AuditIfNotExists"
    selectors = { in = ["member_a"] }
  }
]

# AFTER (required): value key + list-of-object selectors with explicit kind
overrides = [
  {
    value     = "AuditIfNotExists"
    selectors = [
      { kind = "policyDefinitionReferenceId", in = ["member_a"] }
    ]
  }
]
```

- `value` replaces `effect` as the override payload key
- `selectors` is always a list; each selector declares its `kind`
  (`policyDefinitionReferenceId`; omitted kind defaults to it per provider schema)
- `resource_selectors.selectors.kind` is required
  (`resourceLocation`, `resourceType`, `resourceWithoutLocation`)
- maximum 10 entries per input (enforced)
