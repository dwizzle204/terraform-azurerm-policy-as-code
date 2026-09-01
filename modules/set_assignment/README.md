<!-- BEGIN_TF_DOCS -->
# POLICY INITIATIVE ASSIGNMENT MODULE

Assignments can be scoped from overarching management groups right down to individual resources by settings the `assignment_scope`.

## Role Definitions & Assignments

A role assignment will be automatically created if any member definition contains a list of `roleDefinitionIds`. This can be omitted with `skip_role_assignment=true`, or to assign roles at a different scope to that of the policy assignment use: `role_assignment_scope`.

A remediation task is **not** created automatically: remediation is opt-in via `remediate_effects` / `remediation_reference_ids` (see [Remediation lifecycle](#remediation-lifecycle-1-3)) and additionally requires a viable identity/RBAC path.

For a cleaner solution, a list of `aad_group_remediation_object_ids` can be supplied for System Assigned Identity membership in favour of role assignments, assuming the appropriate RBAC controls already exist for that group. More info on role assignments can be found in the [main README](../../README.md#role-assignments)

## Assignment Effects

The `assignment_effect` parameter is useful when an initiative contains multiple effects of the same type and `merge_effects=true`, ensuring that all `member_definitions` are assigned with the same effect.

- Omit `assignment_effect` to use each definition's default effect stored in its policy parameters.
- Specify effects individually by setting them in `assignment_parameters` for more granular control.

### Per-member effective effect (issue #65)

Azure passes initiative parameters to specific member definitions through each
reference's `parameters` mapping; an initiative-level parameter never
implicitly replaces every member's effect. This module therefore resolves the
**effective effect per member** for remediation eligibility:

| Source | Applies to |
|--------|------------|
| `policyEffect` override scoped by `policyDefinitionReferenceId` | the matching member reference (last matching override wins) |
| `assignment_effect` | only members wired to `[parameters('effect')]` |
| member `parameter_values.effect` (interpolation or literal) | that member |
| member policy rule literal effect (`declared_effect`) | that member, when no effect parameter exists |
| resourceLocation-scoped overrides (alone or mixed with a reference selector) | effect is resource-dependent: automatic selection is suppressed unless `location_filters` prove the override cannot apply; explicit `remediation_reference_ids` remain the opt-in path |
| empty-selector overrides (no selectors at all) | unconditional global override: the override value replaces every member's effect |

Literal `DeployIfNotExists` / `Modify` policy rules are auto-detected for
remediation even without an effect parameter; `Audit` / `Deny` / `Disabled`
remain excluded.

## Override contract

The `overrides` input is a `policyEffect`-only abstraction. This module supports
AzureRM `>= 4.35`; AzureRM 4.43 (September 2025) introduced configurable
`override.kind` (including `policyVersion`), which is intentionally not exposed
here. Supporting `policyVersion` requires raising the provider floor to 4.43+.
If additional kinds
are supported in future, remediation effect calculation must ignore non-
`policyEffect` overrides and the provider compatibility floor will be reviewed.



**Direct vs initiative assignments:** `policyDefinitionReferenceId` selectors
select policy definitions **within an initiative assignment** and are only
valid on the [`set_assignment`](../set_assignment) module; the
[`def_assignment`](../def_assignment) module rejects them at plan time.



**Conjunctive selectors:** Azure ANDs all selectors within one override, so
multiple `policyDefinitionReferenceId` selectors must **all** match the member
reference for the override to apply; a contradictory selector pair (e.g.
`in`/`not_in` on the same reference) never applies.

**`resourceWithoutLocation` selectors** only support the value
`subscriptionLevelResources` (enforced at plan time).

## Examples

### Custom Policy Initiative Assignment with Not-Scope and Overrides (preview)

The optional `overrides` property allows you to change the effect of a member definition without modifying the underlying policy definition or using a parameterized effect in the policy definition.

> 📘 [Microsoft Docs: Azure Policy assignment structure (Overrides)](https://learn.microsoft.com/en-us/azure/governance/policy/concepts/assignment-structure#overrides-preview)
> 💡 **Note:** This module also supports Resource selectors (preview), see the [`def_assignment`](../def_assignment) module for an example input

```hcl
module org_mg_configure_asc_initiative {
  source                 = "../../modules/set_assignment"
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
  source           = "../../modules/set_assignment"
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
  source           = "../../modules/set_assignment"
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

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.11 |
| azurerm | >= 4.35 |



## Resources

| Name | Type |
|------|------|
| [azuread_group_member.remediation](https://registry.terraform.io/providers/hashicorp/azuread/latest/docs/resources/group_member) | resource |
| [azurerm_management_group_policy_assignment.set](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_assignment) | resource |
| [azurerm_management_group_policy_remediation.rem](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/management_group_policy_remediation) | resource |
| [azurerm_resource_group_policy_assignment.set](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_assignment) | resource |
| [azurerm_resource_group_policy_remediation.rem](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group_policy_remediation) | resource |
| [azurerm_resource_policy_assignment.set](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_policy_assignment) | resource |
| [azurerm_resource_policy_remediation.rem](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_policy_remediation) | resource |
| [azurerm_role_assignment.remediation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_subscription_policy_assignment.set](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_assignment) | resource |
| [azurerm_subscription_policy_remediation.rem](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subscription_policy_remediation) | resource |
| [terraform_data.remediation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [terraform_data.set_assign_replace](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| aad_group_remediation_object_ids | List of Azure AD Group Object Ids for the System Assigned Identity to be a member of. Omit this to use role_assignments | `list(string)` | `[]` | no |
| collision_resistant_naming | Append a deterministic 8-character hash of (scope, initiative identity) to the assignment name so distinct logical assignments sharing a long prefix cannot collide. **Enabling this changes assignment names and forces replacement of existing assignments** | `bool` | `false` | no |
| assignment_description | A description to use for the Policy Assignment, defaults to initiative description. Changing this forces a new resource to be created | `string` | `null` | no |
| assignment_display_name | The policy assignment display name, defaults to initiative display_name. Changing this forces a new resource to be created | `string` | `null` | no |
| assignment_effect | The effect of the set assignment. Useful when the initiative has multiple effects of the same type and 'merge_effects=true'. Omit this to use each definitions default effect or populate individually at 'assignment_parameters' | `string` | `null` | no |
| assignment_enforcement_mode | Control whether the assignment is enforced | `bool` | `true` | no |
| assignment_location | The Azure location where this policy assignment should exist, required when an Identity is assigned. Defaults to West Europe. Changing this forces a new resource to be created | `string` | `"westeurope"` | no |
| assignment_metadata | The optional metadata for the policy assignment. | `any` | `null` | no |
| assignment_name | The name which should be used for this Policy Assignment, defaults to initiative name. Changing this forces a new Policy Assignment to be created | `string` | `null` | no |
| assignment_not_scopes | A list of the Policy Assignment's excluded scopes. Must be full resource IDs | `list(string)` | `[]` | no |
| assignment_parameters | The policy assignment parameters. Changing this forces a new resource to be created | `any` | `null` | no |
| assignment_scope | The scope at which the policy initiative will be assigned. Must be full resource IDs. Changing this forces a new resource to be created | `string` | n/a | yes |
| failure_percentage | (Optional) A number between 0.0 to 1.0 representing the percentage failure threshold. The remediation will fail if the percentage of failed remediation operations (i.e. failed deployments) exceeds this threshold. | `number` | `null` | no |
| identity_ids | Optional list of User Managed Identity IDs which should be assigned to the Policy Initiative | `list(string)` | `null` | no |
| initiative | Policy Initiative resource node | `any` | n/a | yes |
| location_filters | Optional list of the resource locations that will be remediated | `list(string)` | `[]` | no |
| non_compliance_messages | The optional non-compliance message(s). Key/Value pairs map as policy_definition_reference_id = 'content', use null = 'content' to specify the Default non-compliance message for all member definitions. | `any` | `{}` | no |
| overrides | Optional list of assignment Overrides (preview), max 10. Allows you to change the effect of a policy definition without modifying the underlying policy definition or using a parameterized effect in the policy definition | `list(any)` | `[]` | no |
| parallel_deployments | (Optional) Determines how many resources to remediate at any given time. Can be used to increase or reduce the pace of the remediation. If not provided, the default parallel deployments value is used. | `number` | `null` | no |
| re_evaluate_compliance | Sets the remediation task resource_discovery_mode for policies that DeployIfNotExists and Modify. false = 'ExistingNonCompliant' and true = 'ReEvaluateCompliance'. Defaults to false. Applies at subscription scope and below | `bool` | `false` | no |
| remediation_scope | The scope at which the remediation tasks will be created. Must be full resource IDs. Defaults to the policy assignment scope. Changing this forces a new resource to be created | `string` | `null` | no |
| resource_count | (Optional) Determines the max number of resources that can be remediated by the remediation job. If not provided, the default resource count is used. | `number` | `null` | no |
| resource_selectors | Optional list of Resource selectors (preview), max 10. These facilitate safe deployment practices (SDP) by enabling you to gradually roll out policy assignments based on factors like resource location, resource type, or whether a resource has a location | `list(any)` | `[]` | no |
| role_assignment_scope | The scope at which role definition(s) will be assigned, defaults to Policy Assignment Scope. Must be full resource IDs. Ignored when using Managed Identities. Changing this forces a new resource to be created | `string` | `null` | no |
| role_definition_ids | List of Role definition ID's for the System Assigned Identity. Omit this to use those located in policy definitions. Ignored when using Managed Identities. Changing this forces a new resource to be created | `list(string)` | `[]` | no |
| skip_remediation | Should the module skip creation of a remediation task for policies that DeployIfNotExists and Modify | `bool` | `false` | no |
| skip_role_assignment | Should the module skip creation of role assignment for policies that DeployIfNotExists and Modify | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| definition_reference_ids | The Member Definition Reference Ids |
| definition_references | The Member Definition References |
| id | The Policy Assignment Id |
| principal_id | The Principal Id of this Policy Assignment's Managed Identity if type is SystemAssigned |
| remediation_tasks | The Remediation Task Ids and related Policy Definition Ids |
<!-- END_TF_DOCS -->

## Migration notes

### Collision-resistant assignment names (#2)

`collision_resistant_naming` defaults to `false`, preserving today's truncation behavior byte-for-byte. Enabling it changes the computed assignment name, which forces replacement (destroy/create) of existing assignments — plan during a maintenance window and expect re-creation, not in-place updates. The hash covers scope + initiative identity + requested name only; cosmetic display name/description changes never affect it.

## Remediation lifecycle (#1, #3)

Remediation is **opt-in and effect-aware**:

| Input | Meaning |
|-------|---------|
| `remediate_effects` | Member effects eligible for remediation tasks. Default `[]` (disabled). Only `DeployIfNotExists` / `Modify` are valid |
| `remediation_reference_ids` | Explicit member reference ids to remediate when the resolved effect is unresolved (empty). Known non-remediable effects remain rejected even when explicitly listed; unknown ids fail the plan |
| `skip_remediation` | Master switch; suppresses all remediation regardless of the above |

Per-member effect resolution reads the member's `parameter_values.effect.value`, falls back to the policy rule's literal effect (`declared_effect`), then applies `assignment_effect` only to members wired to `[parameters('effect')]`, and finally applies `policyEffect` overrides. See [Assignment Effects](#assignment-effects).

### Minimum privileges per deployment mode

| Mode | Privileges required by deployment principal |
|------|---------------------------------------------|
| Assignment only (`remediate_effects=[]`, no identity) | Policy assignment write at scope |
| + managed identity | As above + Microsoft.ManagedIdentity write + role assignment read at location |
| + module-managed RBAC | As above + role assignment write for each `role_definition_ids` entry |
| + remediation | As above + `Microsoft.PolicyInsights/remediations/*` at remediation scope |

### Externally managed pattern

Use `identity_ids` (pre-created user-assigned identity) plus
`skip_role_assignment = true` with your own RBAC provisioning, then set
`remediate_effects` to hand execution to this module only.

### Migration

Pre-#1 behavior approximated by setting `remediate_effects = ["DeployIfNotExists", "Modify"]`.

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
