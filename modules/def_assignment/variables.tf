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

  validation {
    condition     = can(regex("(?i)^(?:/providers/Microsoft\\.Management/managementGroups/[^/]+|/subscriptions/[^/]+(?:/resourceGroups/[^/]+(?:/providers/.+)?|/providers/.+)?)$", var.assignment_scope))
    error_message = "assignment_scope must be a valid Azure scope: management group (/providers/Microsoft.Management/managementGroups/<name>), subscription (/subscriptions/<id>), resource group (/subscriptions/<id>/resourceGroups/<name>), or resource (/subscriptions/<id>/resourceGroups/<name>/providers/...)."
  }
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
    condition     = var.assignment_metadata == null || (can({ for k, v in var.assignment_metadata : k => v }) && !can(tolist(var.assignment_metadata))) || try(can({ for k, v in jsondecode(var.assignment_metadata) : k => v }) && !can(tolist(jsondecode(var.assignment_metadata))), false)
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

variable "overrides" {
  description = "Optional list of assignment Overrides (preview), max 10. Allows you to change the effect of a policy definition without modifying the underlying policy definition or using a parameterized effect in the policy definition. Direct policy-definition assignments are NOT initiative members, so `policyDefinitionReferenceId` selectors are invalid here (they select definitions within an initiative assignment) and are rejected at plan time; only `resourceLocation` selectors are supported. An override with no selectors is a global override."
  type = list(object({
    value = string
    selectors = optional(list(object({
      kind   = optional(string)
      in     = optional(list(string))
      not_in = optional(list(string))
    })), [])
  }))
  default = []

  validation {
    condition = alltrue(flatten([
      for o in var.overrides : [
        for s in coalesce(o.selectors, []) :
        s.in == null || s.not_in == null
      ]
    ]))
    error_message = "Override selectors cannot specify both in and not_in."
  }

  validation {
    condition = alltrue(flatten([
      for o in var.overrides : flatten([
        for s in coalesce(o.selectors, []) : [
          length(coalesce(s.in, [])) <= 50,
          length(coalesce(s.not_in, [])) <= 50
        ]
      ])
    ]))
    error_message = "Override selector in and not_in lists support a maximum of 50 values each."
  }

  # issue #69: policyDefinitionReferenceId selects policy definitions WITHIN an
  # initiative assignment; a direct policy-definition assignment has no member
  # reference ids, so this selector kind is semantically invalid here and is
  # rejected at plan time instead of being compared to the definition name.
  # NOTE: s.kind must be non-null — an omitted kind is treated by the AzureRM
  # provider as "policyDefinitionReferenceId", so coalescing null to a valid
  # value here would silently re-open that bypass.
  validation {
    condition = alltrue(flatten([
      for o in var.overrides : [
        for s in coalesce(o.selectors, []) :
        s.kind != null
      ]
    ]))
    error_message = "Override selector kind must be explicitly set for direct policy-definition assignments; an omitted kind defaults to policyDefinitionReferenceId (initiative-scoped) and is not valid here."
  }

  validation {
    condition = alltrue(flatten([
      for o in var.overrides : [
        for s in coalesce(o.selectors, []) :
        coalesce(s.kind, "policyDefinitionReferenceId") != "policyDefinitionReferenceId"
      ]
    ]))
    error_message = "policyDefinitionReferenceId override selectors are only valid on initiative (set_assignment) assignments; a direct policy-definition assignment has no member reference ids. Use resourceLocation selectors or an override with no selectors (global)."
  }

  validation {
    condition = alltrue(flatten([
      for o in var.overrides : [
        for s in coalesce(o.selectors, []) :
        contains(["resourceLocation"], coalesce(s.kind, "policyDefinitionReferenceId"))
      ]
    ]))
    error_message = "Override selector kind must be resourceLocation for direct policy-definition assignments (policyDefinitionReferenceId is initiative-scoped)."
  }

  validation {
    condition     = length(var.overrides) <= 10
    error_message = "Overrides supports a maximum of 10 entries."
  }
}

variable "resource_selectors" {
  description = "Optional list of Resource selectors (preview), max 10. These facilitate safe deployment practices (SDP) by enabling you to gradually roll out policy assignments based on factors like resource location, resource type, or whether a resource has a location. Selector kind must be one of: resourceLocation, resourceType, resourceWithoutLocation"
  type = list(object({
    name = optional(string)
    selectors = list(object({
      kind   = string
      in     = optional(list(string))
      not_in = optional(list(string))
    }))
  }))
  default = []

  validation {
    condition = alltrue(flatten([
      for rs in var.resource_selectors : [
        for s in rs.selectors :
        contains(["resourceLocation", "resourceType", "resourceWithoutLocation"], s.kind)
      ]
    ]))
    error_message = "Resource selector kind must be one of: resourceLocation, resourceType, resourceWithoutLocation."
  }

  validation {
    condition = alltrue(flatten([
      for rs in var.resource_selectors : [
        length([for s in rs.selectors : s.kind]) == length(toset([for s in rs.selectors : s.kind])),
        !contains([for s in rs.selectors : s.kind], "resourceLocation") || !contains([for s in rs.selectors : s.kind], "resourceWithoutLocation")
      ]
    ]))
    error_message = "Resource selector kinds must be unique and cannot combine resourceLocation with resourceWithoutLocation."
  }

  validation {
    condition = alltrue(flatten([
      for rs in var.resource_selectors : flatten([
        for s in rs.selectors : [
          s.in == null || s.not_in == null,
          length(coalesce(s.in, [])) <= 50,
          length(coalesce(s.not_in, [])) <= 50,
          # issue #69: Azure documents resourceWithoutLocation selectors as
          # supporting only the value 'subscriptionLevelResources'.
          s.kind != "resourceWithoutLocation" || length(coalesce(s.in, [])) == 0 || length(setsubtract(coalesce(s.in, []), ["subscriptionLevelResources"])) == 0,
          s.kind != "resourceWithoutLocation" || length(coalesce(s.not_in, [])) == 0 || length(setsubtract(coalesce(s.not_in, []), ["subscriptionLevelResources"])) == 0
        ]
      ])
    ]))
    error_message = "Resource selector in and not_in lists are mutually exclusive, support a maximum of 50 values each, and resourceWithoutLocation only supports the value 'subscriptionLevelResources'."
  }

  validation {
    condition     = length(var.resource_selectors) <= 10
    error_message = "Resource Selectors supports a maximum of 10 entries."
  }
}


variable "identity_ids" {
  type        = list(string)
  description = "Optional list of User Managed Identity IDs which should be assigned to the Policy Definition. Must be null (SystemAssigned) or contain at least one valid User Assigned Managed Identity resource ID."
  default     = null

  # issue #69: an empty list is non-null and would select UserAssigned with zero
  # identity ids, which AzureRM rejects at apply. Fail fast instead, and require
  # every supplied id to be a valid UAMI ARM resource id.
  validation {
    condition = var.identity_ids == null ? true : (
      length(var.identity_ids) > 0
      && alltrue([
        for id in var.identity_ids :
        can(regex("(?i)^/subscriptions/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/resourcegroups/[^/]+/providers/microsoft\\.managedidentity/userassignedidentities/[^/]+$", trimspace(id)))
      ])
    )
    error_message = "identity_ids must be null (for SystemAssigned) or contain at least one valid User Assigned Managed Identity resource ID matching /subscriptions/{subscriptionId}/resourceGroups/{resourceGroup}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/{name}."
  }
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

  validation {
    condition     = var.remediation_scope == null || can(regex("(?i)^(?:/providers/Microsoft\\.Management/managementGroups/[^/]+|/subscriptions/[^/]+(?:/resourceGroups/[^/]+(?:/providers/.+)?|/providers/.+)?)$", var.remediation_scope))
    error_message = "remediation_scope must be a valid Azure scope: management group, subscription, resource group, or resource."
  }
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
  description = "Explicit definition reference ids to remediate when the resolved effect is unresolved (empty). Known non-remediable effects (Audit, Deny, etc.) remain rejected even when explicitly listed. Unknown ids fail the plan. Ignored when empty."
  default     = []
}

variable "skip_role_assignment" {
  type        = bool
  description = "Should the module skip creation of role assignment for policies that DeployIfNotExists and Modify"
  default     = false
}

locals {
  # Normalize Azure locations before proving selector disjointness. Friendly/display
  # names are intentionally not considered provably canonical, so remediation
  # remains suppressed rather than relying on an unsafe equivalence assumption.
  normalized_location_filters = [for v in var.location_filters : lower(trimspace(v))]

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
  # normalize JSON-string input so the boundary jsonencode() never double-encodes (#4)
  assignment_metadata_normalized = var.assignment_metadata == null ? null : try(jsondecode(var.assignment_metadata), var.assignment_metadata)
  _assignment_metadata_json      = local.assignment_metadata_normalized != null ? jsonencode(local.assignment_metadata_normalized) : jsonencode(try(jsondecode(var.definition.metadata), {}))
  metadata                       = local._assignment_metadata_json

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
  # issue #69: forward trimmed UAMI ids to resources — validation
  # trimspace()s for matching but raw values were previously forwarded.
  identity_ids_normalized = var.identity_ids != null ? [for id in var.identity_ids : trimspace(id)] : null

  identity_type = length(try(coalescelist(var.role_definition_ids, lookup(try(jsondecode(var.definition.policy_rule).then.details, {}), "roleDefinitionIds", [])), [])) > 0 ? var.identity_ids != null ? { type = "UserAssigned" } : { type = "SystemAssigned" } : {}

  # try to use policy definition roles if explicit roles are omitted
  role_definition_ids = var.skip_role_assignment == false && length(var.aad_group_remediation_object_ids) == 0 && try(values(local.identity_type)[0], "") == "SystemAssigned" ? try(coalescelist(var.role_definition_ids, lookup(try(jsondecode(var.definition.policy_rule).then.details, {}), "roleDefinitionIds", [])), []) : []

  # issue #62: assignment_effect is an assignment-time value for a parameter
  # DECLARED by the assigned definition (Azure assignment parameters are values
  # for definition/initiative parameters). Injecting an "effect" assignment
  # parameter when the definition declares no effect parameter is not a valid
  # Azure payload and makes local remediation selection disagree with the real
  # policy effect. Fail fast naming the offending key.
  effect_parameter_declared = contains(keys(local.definition_parameters_decoded), "effect")
  # issue #62: unknown assignment_parameters keys are values for parameters the
  # definition does not declare; Azure rejects such payloads at apply.
  unknown_assignment_parameter_keys = var.assignment_parameters != null ? setsubtract(keys(var.assignment_parameters), keys(local.definition_parameters_decoded)) : []

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
  # issue #65: assignment_effect is only a valid remediation classifier when the
  # policy rule's effect is actually wired to the declared parameter
  # (then.effect == "[parameters('effect')]"). A declared-but-unused parameter
  # plus a literal Audit rule stays Audit: the assignment parameter value must
  # never fabricate remediation eligibility the policy will not have. Literal
  # rule effects keep driving eligibility regardless of assignment parameters.
  policy_rule_effect_raw    = try(tostring(try(jsondecode(var.definition.policy_rule), var.definition.policy_rule).then.effect), "")
  effect_wired_to_parameter = lower(local.policy_rule_effect_raw) == "[parameters('effect')]"
  raw_effect = (
    var.assignment_effect != null && local.effect_wired_to_parameter ? var.assignment_effect :
    var.assignment_effect != null ? local.policy_rule_effect_raw :
    local.policy_rule_effect_raw
  )
  interpolated_parameter = can(regex("^\\[parameters\\('(.+?)'\\)\\]$", local.raw_effect)) ? regex("^\\[parameters\\('(.+?)'\\)\\]$", local.raw_effect)[0] : null
  base_effect = lower(
    local.interpolated_parameter != null ?
    tostring(try(
      var.assignment_parameters[local.interpolated_parameter],
      local.definition_parameters_decoded[local.interpolated_parameter].defaultValue,
      ""
    )) :
    local.raw_effect
  )
  # issue #65/#69: policyEffect overrides replace this definition's effective
  # effect. policyDefinitionReferenceId selectors are rejected at plan time for
  # direct definition assignments (issue #69), so every remaining selector is a
  # resourceLocation selector and an override with NO selectors is an
  # unconditional global override. Azure ANDs all selectors within one override,
  # so selector groups are evaluated conjunctively (mirroring set_assignment):
  #   - provably disjoint: location_filters is non-empty AND every resourceLocation
  #     selector scopes by `in` AND at least one of those `in` sets does not
  #     intersect location_filters — the override cannot apply to ANY remediated
  #     resource and is excluded from effect replacement entirely.
  #   - provably applies: the override has no selectors, OR location_filters is
  #     non-empty AND every resourceLocation selector scopes by `in` AND every
  #     one of those `in` sets intersects location_filters (all locations in the
  #     filter are covered) AND every location in those sets is covered by the
  #     filter — its value replaces the definition's base effect.
  #   - anything else (a `not_in` resourceLocation selector, an override that
  #     covers only some filtered locations, or selectors with empty
  #     location_filters) is resource-dependent/ambiguous: the effective effect
  #     cannot be proven for a given remediated resource, so automatic
  #     remediation is suppressed. Explicit remediation_reference_ids remain
  #     the opt-in path.
  definition_override_has_selectors = {
    for idx, o in var.overrides : idx => length(coalesce(o.selectors, [])) > 0
  }
  definition_override_all_in = {
    for idx, o in var.overrides : idx => (
      !local.definition_override_has_selectors[idx]
      || alltrue([
        for s in coalesce(o.selectors, []) : length(coalesce(s.in, [])) > 0
      ])
    )
  }
  # issue #67: disjointness may only be PROVEN when every location value on both
  # sides is already in canonical form (lowercase alphanumeric/hyphen after
  # trim+lower). Friendly names such as "East US 2" are semantically equal to
  # "eastus2" in Azure, so a raw string mismatch must suppress automatic
  # remediation instead of proving non-applicability.
  definition_override_locations_canonical = {
    for idx, o in var.overrides : idx => alltrue([
      for v in concat(
        flatten([for s in coalesce(o.selectors, []) : coalesce(s.in, [])]),
        var.location_filters
      ) : can(regex("^[a-z0-9-]+$", lower(trimspace(v))))
    ])
  }
  definition_override_disjoint = {
    for idx, o in var.overrides : idx => (
      local.definition_override_has_selectors[idx]
      && local.definition_override_all_in[idx]
      && length(var.location_filters) > 0
      && local.definition_override_locations_canonical[idx]
      && length([
        for s in coalesce(o.selectors, []) :
        s if length(setintersection([for v in coalesce(s.in, []) : lower(trimspace(v))], local.normalized_location_filters)) == 0
      ]) > 0
    )
  }
  definition_override_applies = {
    for idx, o in var.overrides : idx => (
      !local.definition_override_has_selectors[idx]
      || (
        local.definition_override_all_in[idx]
        && local.definition_override_locations_canonical[idx]
        && length(var.location_filters) > 0
        # The override provably applies only when the union of its `in` sets
        # covers the ENTIRE location_filters set (every remediated location is
        # affected) and vice versa every selector set is fully covered by the
        # filters. Any partial coverage is resource-dependent: suppress.
        && length(setunion(flatten([
          for s in coalesce(o.selectors, []) : [for v in coalesce(s.in, []) : lower(trimspace(v))]
        ]))) >= length(local.normalized_location_filters)
        && alltrue([
          for s in coalesce(o.selectors, []) :
          length(setintersection(
            [for v in coalesce(s.in, []) : lower(trimspace(v))],
            local.normalized_location_filters
          )) == length(local.normalized_location_filters)
        ])
      )
    )
  }
  definition_override_matches = [
    for idx, o in var.overrides :
    lower(o.value) if !local.definition_override_disjoint[idx] && local.definition_override_applies[idx]
  ]
  definition_override_effect = length(local.definition_override_matches) > 0 ? element(local.definition_override_matches, length(local.definition_override_matches) - 1) : null
  # issue #69: an override that neither provably applies nor is provably
  # disjoint is resource-dependent for the remediated resources — suppress
  # automatic remediation rather than guessing.
  definition_scope_ambiguous_override = length([
    for idx, o in var.overrides :
    idx if !local.definition_override_disjoint[idx] && !local.definition_override_applies[idx]
  ]) > 0
  effective_effect = (
    local.definition_scope_ambiguous_override ? "" :
    local.definition_override_effect != null ? local.definition_override_effect :
    local.base_effect
  )
  # Explicit references are an escape hatch only when the effect is unresolved;
  # known effects remain subject to Azure's remediation-safe effect set.
  definition_eligible = (
    contains(["deployifnotexists", "modify"], local.effective_effect) && (
      contains([for e in var.remediate_effects : lower(e)], local.effective_effect) || contains(var.remediation_reference_ids, try(var.definition.name, ""))
    )
  ) || (contains(var.remediation_reference_ids, try(var.definition.name, "")) && local.effective_effect == "")
  unknown_remediation_references = (
    length(var.remediation_reference_ids) > 0 && !contains(var.remediation_reference_ids, try(var.definition.name, "")) ?
    file("[ERROR] def_assignment: remediation_reference_ids [${join(", ", var.remediation_reference_ids)}] do not include this definition ('${try(var.definition.name, "")}'). Valid id: '${try(var.definition.name, "")}'.") :
    true
  )
  # issue #62: remediation under DoNotEnforce is Azure-supported (manual
  # remediation of deployIfNotExists works with enforcementMode = DoNotEnforce),
  # so assignment_enforcement_mode no longer gates remediation task creation.
  # Request-time enforcement stays decoupled from explicitly requested remediation.
  create_remediation = var.skip_remediation == false && length(local.identity_type) > 0 && local.unknown_remediation_references == true && local.definition_eligible ? 1 : 0

  # assignment location is required when identity is specified
  assignment_location = length(local.identity_type) > 0 ? var.assignment_location : null

  # evaluate policy assignment scope from resource identifier
  assignment_scope = {
    mg       = length(regexall("(?i)(/managementGroups/)", var.assignment_scope)) > 0 ? 1 : 0,
    sub      = length(split("/", var.assignment_scope)) == 3 ? 1 : 0,
    rg       = length(regexall("(?i)(/managementGroups/)", var.assignment_scope)) < 1 ? length(split("/", var.assignment_scope)) == 5 ? 1 : 0 : 0,
    resource = length(split("/", var.assignment_scope)) >= 6 ? 1 : 0,
  }

  # evaluate remediation scope from resource identifier
  resource_discovery_mode = var.re_evaluate_compliance == true ? "ReEvaluateCompliance" : "ExistingNonCompliant"
  remediation_scope       = coalesce(var.remediation_scope, var.assignment_scope)
  remediate = {
    mg       = length(regexall("(?i)(/managementGroups/)", local.remediation_scope)) > 0 ? 1 : 0,
    sub      = length(split("/", local.remediation_scope)) == 3 ? 1 : 0,
    rg       = length(regexall("(?i)(/managementGroups/)", local.remediation_scope)) < 1 ? length(split("/", local.remediation_scope)) == 5 ? 1 : 0 : 0,
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
