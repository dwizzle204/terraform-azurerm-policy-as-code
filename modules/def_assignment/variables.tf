variable "definition" {
  description = "Policy Definition resource node (matches the definition module's `definition` output)"
  type = object({
    id                  = string
    name                = string
    display_name        = optional(string)
    description         = optional(string)
    mode                = optional(string)
    management_group_id = optional(string)
    metadata            = optional(string)
    parameters          = optional(string)
    policy_rule         = optional(string)
  })
}

variable "assignment_scope" {
  type        = string
  description = "The scope at which the policy will be assigned. Must be full resource IDs. Changing this forces a new resource to be created"
}

variable "assignment_not_scopes" {
  type        = list(string)
  description = "A list of the Policy Assignment's excluded scopes. Must be full resource IDs"
  default     = []
}

variable "assignment_name" {
  type        = string
  description = "The name which should be used for this Policy Assignment, defaults to definition name. Changing this forces a new Policy Assignment to be created"
  default     = null
}

variable "assignment_display_name" {
  type        = string
  description = "The policy assignment display name, defaults to definition display_name. Changing this forces a new resource to be created"
  default     = null
}

variable "assignment_description" {
  type        = string
  description = "A description to use for the Policy Assignment, defaults to definition description. Changing this forces a new resource to be created"
  default     = null
}

variable "assignment_effect" {
  type        = string
  description = "The effect of the policy. Changing this forces a new resource to be created"
  default     = null
}

variable "assignment_parameters" {
  # any: parameter values are defined by each policy's own schema
  type        = any
  description = "The policy assignment parameters. Changing this forces a new resource to be created"
  default     = {}
}

variable "assignment_metadata" {
  type        = any
  description = "The optional metadata for the policy assignment."
  default     = null

  validation {
    condition     = var.assignment_metadata == null || can({ for k, v in var.assignment_metadata : k => v }) || can(tostring(var.assignment_metadata))
    error_message = "assignment_metadata must be an object or a JSON-encoded string."
  }
}

variable "assignment_enforcement_mode" {
  type        = bool
  description = "Control whether the assignment is enforced"
  default     = true
}

variable "assignment_location" {
  type        = string
  description = "The Azure location where this policy assignment should exist, required when an Identity is assigned. Defaults to UK South. Changing this forces a new resource to be created"
  default     = "westeurope"
}

variable "non_compliance_message" {
  type        = string
  description = "The optional non-compliance message text."
  default     = null
}

variable "resource_selectors" {
  type        = list(any)
  description = "Optional list of Resource selectors (preview), max 10. These facilitate safe deployment practices (SDP) by enabling you to gradually roll out policy assignments based on factors like resource location, resource type, or whether a resource has a location"
  default     = []
}

variable "identity_ids" {
  type        = list(string)
  description = "Optional list of User Managed Identity IDs which should be assigned to the Policy Definition"
  default     = null
}

variable "re_evaluate_compliance" {
  type        = bool
  description = "Sets the remediation task resource_discovery_mode for policies that DeployIfNotExists and Modify. false = 'ExistingNonCompliant' and true = 'ReEvaluateCompliance'. Defaults to false. Applies at subscription scope and below"
  default     = false
}

variable "remediation_scope" {
  type        = string
  description = "The scope at which the remediation tasks will be created. Must be full resource IDs. Defaults to the policy assignment scope. Changing this forces a new resource to be created"
  default     = null
}

variable "location_filters" {
  type        = list(string)
  description = "Optional list of the resource locations that will be remediated"
  default     = []
}

variable "failure_percentage" {
  type        = number
  description = "(Optional) A number between 0.0 to 1.0 representing the percentage failure threshold. The remediation will fail if the percentage of failed remediation operations (i.e. failed deployments) exceeds this threshold."
  default     = null
}

variable "parallel_deployments" {
  type        = number
  description = "(Optional) Determines how many resources to remediate at any given time. Can be used to increase or reduce the pace of the remediation. If not provided, the default parallel deployments value is used."
  default     = null
}

variable "resource_count" {
  type        = number
  description = "(Optional) Determines the max number of resources that can be remediated by the remediation job. If not provided, the default resource count is used."
  default     = null
}

variable "aad_group_remediation_object_ids" {
  type        = list(string)
  description = "List of Azure AD Group Object Ids for the System Assigned Identity to be a member of. Omit this to use role_assignments"
  default     = []
}

variable "role_definition_ids" {
  type        = list(string)
  description = "List of Role definition ID's for the System Assigned Identity, defaults to roles included in the definition. Ignored when using Managed Identities. Changing this forces a new resource to be created"
  default     = []
}

variable "role_assignment_scope" {
  type        = string
  description = "The scope at which role definition(s) will be assigned, defaults to Policy Assignment Scope. Must be full resource IDs. Ignored when using Managed Identities. Changing this forces a new resource to be created"
  default     = null
}

variable "collision_resistant_naming" {
  type        = bool
  description = "Append a deterministic 8-character hash of (scope, policy/initiative identity) to the assignment name so distinct logical assignments sharing a long prefix cannot collide. Enabling this changes assignment names and forces replacement of existing assignments. Defaults to false (legacy truncation behavior)."
  default     = false
}

variable "skip_remediation" {
  type        = bool
  description = "Should the module skip creation of a remediation task for policies that DeployIfNotExists and Modify"
  default     = false
}

variable "remediate_effects" {
  type        = list(string)
  description = "Policy effects eligible for automatic remediation tasks. Defaults to [] (remediation is opt-in per #1/#3). Only DeployIfNotExists and Modify can be remediated by Azure Policy."
  default     = []

  validation {
    condition     = length([for e in var.remediate_effects : e if !contains(["DeployIfNotExists", "Modify"], e)]) == 0
    error_message = "Only DeployIfNotExists and Modify effects can be remediated."
  }
}

variable "remediation_reference_ids" {
  type        = list(string)
  description = "Explicit definition reference ids (for def_assignment: definition names) to remediate regardless of resolved effect. Unknown ids fail the plan. Ignored when empty."
  default     = []
}

variable "skip_role_assignment" {
  type        = bool
  description = "Should the module skip creation of role assignment for policies that DeployIfNotExists and Modify"
  default     = false
}

locals {
  # assignment_name at MG scope will be trimmed if exceeds 24 characters
  assignment_name_trim = local.assignment_scope.mg > 0 ? 24 : 64
  assignment_name_base = try(lower(coalesce(var.assignment_name, var.definition.name)), "")
  # hash inputs: assignment scope + definition identity + requested name.
  # Cosmetic inputs (display names/descriptions) deliberately do not affect it.
  assignment_name_hash = substr(md5(jsonencode({
    scope  = var.assignment_scope
    member = try(var.definition.name, "")
    name   = coalesce(var.assignment_name, var.definition.name)
  })), 0, 8)
  assignment_name = var.collision_resistant_naming ? (
    length(local.assignment_name_base) > 0 ?
    join("-", [substr(local.assignment_name_base, 0, local.assignment_name_trim - 9), local.assignment_name_hash]) :
    ""
  ) : try(lower(substr(coalesce(var.assignment_name, var.definition.name), 0, local.assignment_name_trim)), "")
  display_name = try(coalesce(var.assignment_display_name, var.definition.display_name), "")
  description  = try(coalesce(var.assignment_description, var.definition.description), "")
  metadata     = jsonencode(try(coalesce(var.assignment_metadata, jsondecode(var.definition.metadata)), {}))

  # convert assignment parameters to the required assignment structure
  parameter_values = var.assignment_parameters != null ? {
    for key, value in var.assignment_parameters :
    key => merge({ value = value })
  } : null

  # merge effect with parameter_values if specified, will use definition defaults if omitted
  parameters = var.assignment_effect != null ? jsonencode(merge(local.parameter_values, { effect = { value = var.assignment_effect } })) : (local.parameter_values != null ? jsonencode(local.parameter_values) : null)

  # create the optional non-compliance message contents block if present
  non_compliance_message = contains(["All", "Indexed"], try(var.definition.mode, "")) ? { content = try(coalesce(var.non_compliance_message, local.description, local.display_name, "Flagged by Policy: ${local.assignment_name}", "")) } : {}

  # determine if a managed identity should be created with this assignment
  identity_type = length(try(coalescelist(var.role_definition_ids, lookup(try(jsondecode(var.definition.policy_rule).then.details, {}), "roleDefinitionIds", [])), [])) > 0 ? var.identity_ids != null ? { type = "UserAssigned" } : { type = "SystemAssigned" } : {}

  # try to use policy definition roles if explicit roles are omitted
  role_definition_ids = var.skip_role_assignment == false && length(var.aad_group_remediation_object_ids) == 0 && try(values(local.identity_type)[0], "") == "SystemAssigned" ? try(coalescelist(var.role_definition_ids, lookup(try(jsondecode(var.definition.policy_rule).then.details, {}), "roleDefinitionIds", [])), []) : []

  # if creating role assignments also create a remediation task for policies with DeployIfNotExists and Modify effects
  # issue #1/#3: remediation is opt-in and effect-aware. Effective effect comes
  # from the assignment override or the policy rule; explicit remediation_reference_ids
  # override effect resolution for this single definition.
  # coalesce skips empty strings so use an explicit null-guard for the override
  # issue #1/#3: robust effect resolution (see set_assignment counterpart).
  # Handles literal effects in any casing and initiative interpolations
  # "[parameters('x')]" resolved against assignment_parameters first, then the
  # definition parameter defaultValue. Unresolvable => not remediable unless
  # explicitly selected via remediation_reference_ids.
  definition_parameters_decoded = try(jsondecode(var.definition.parameters), var.definition.parameters, {})
  # note: not coalesce() - it rejects empty strings, which are a valid
  # "no effect declared" outcome from try()
  raw_effect             = var.assignment_effect != null ? var.assignment_effect : try(jsondecode(var.definition.policy_rule).then.effect, "")
  interpolated_parameter = can(regex("^\\[parameters\\('(.+?)'\\)\\]$", local.raw_effect)) ? regex("^\\[parameters\\('(.+?)'\\)\\]$", local.raw_effect)[0] : null
  effective_effect = lower(
    local.interpolated_parameter != null ?
    tostring(try(
      var.assignment_parameters[local.interpolated_parameter],
      local.definition_parameters_decoded[local.interpolated_parameter].defaultValue,
      ""
    )) :
    local.raw_effect
  )
  definition_eligible = contains([for e in var.remediate_effects : lower(e)], local.effective_effect) || contains(var.remediation_reference_ids, try(var.definition.name, ""))
  unknown_remediation_references = (
    length(var.remediation_reference_ids) > 0 && !contains(var.remediation_reference_ids, try(var.definition.name, "")) ?
    file("[ERROR] def_assignment: remediation_reference_ids [${join(", ", var.remediation_reference_ids)}] do not include this definition ('${try(var.definition.name, "")}'). Valid id: '${try(var.definition.name, "")}'.") :
    true
  )
  create_remediation = var.assignment_enforcement_mode == true && var.skip_remediation == false && length(local.identity_type) > 0 && local.unknown_remediation_references == true && local.definition_eligible ? 1 : 0

  # assignment location is required when identity is specified
  assignment_location = length(local.identity_type) > 0 ? var.assignment_location : null

  # evaluate policy assignment scope from resource identifier
  assignment_scope = {
    mg       = length(regexall("(\\/managementGroups\\/)", var.assignment_scope)) > 0 ? 1 : 0,
    sub      = length(split("/", var.assignment_scope)) == 3 ? 1 : 0,
    rg       = length(regexall("(\\/managementGroups\\/)", var.assignment_scope)) < 1 ? length(split("/", var.assignment_scope)) == 5 ? 1 : 0 : 0,
    resource = length(split("/", var.assignment_scope)) >= 6 ? 1 : 0,
  }

  # evaluate remediation scope from resource identifier
  resource_discovery_mode = var.re_evaluate_compliance == true ? "ReEvaluateCompliance" : "ExistingNonCompliant"
  remediation_scope       = coalesce(var.remediation_scope, var.assignment_scope)
  remediate = {
    mg       = length(regexall("(\\/managementGroups\\/)", local.remediation_scope)) > 0 ? 1 : 0,
    sub      = length(split("/", local.remediation_scope)) == 3 ? 1 : 0,
    rg       = length(regexall("(\\/managementGroups\\/)", local.remediation_scope)) < 1 ? length(split("/", local.remediation_scope)) == 5 ? 1 : 0 : 0,
    resource = length(split("/", local.remediation_scope)) >= 6 ? 1 : 0,
  }

  # evaluate assignment outputs
  assignment = try(
    azurerm_management_group_policy_assignment.def[0],
    azurerm_subscription_policy_assignment.def[0],
    azurerm_resource_group_policy_assignment.def[0],
    azurerm_resource_policy_assignment.def[0],
  "")
  remediation_id = try(
    azurerm_management_group_policy_remediation.rem[0].id,
    azurerm_subscription_policy_remediation.rem[0].id,
    azurerm_resource_group_policy_remediation.rem[0].id,
    azurerm_resource_policy_remediation.rem[0].id,
  "")
}
