variable "initiative" {
  description = "Policy Initiative resource node (matches the initiative module's `initiative` output)"
  type = object({
    id                  = string
    name                = string
    display_name        = optional(string)
    description         = optional(string)
    management_group_id = optional(string)
    parameters          = optional(any) # arbitrary merged parameter schema object
    metadata            = optional(string)
    role_definition_ids = optional(list(string))
    replace_trigger     = optional(string)
    reference_ids       = optional(list(string))
    policy_definition_reference = optional(list(object({
      policy_definition_id = string
      reference_id         = string
      parameter_values     = optional(string)
      version              = optional(string)
      # issue #65: normalized effect source from the policy rule (literal effect,
      # "[parameters('effect')]", or "" when unresolved). Optional so externally
      # managed initiative data without rule visibility remains accepted.
      declared_effect = optional(string)
      # issue #65 (Codex P1): authoritative signal that the member's policy rule
      # actually consumes the initiative effect parameter. A member can carry a
      # parameter_values.effect mapping purely to satisfy a REQUIRED (no
      # defaultValue) parameter contract while its rule effect stays literal;
      # such a mapping must not make assignment_effect eligible. Optional with a
      # parameter_values-based fallback for external initiative data.
      effect_parameter_wired = optional(bool)
    })))
  })
}

variable "assignment_scope" {
  type        = string
  description = "The scope at which the policy initiative will be assigned. Must be full resource IDs. Changing this forces a new resource to be created"

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
  description = "The name which should be used for this Policy Assignment, defaults to initiative name. Changing this forces a new Policy Assignment to be created"
  default     = null
}

variable "assignment_display_name" {
  type        = string
  description = "The policy assignment display name, defaults to initiative display_name. Changing this forces a new resource to be created"
  default     = null
}

variable "assignment_description" {
  type        = string
  description = "A description to use for the Policy Assignment, defaults to initiative description. Changing this forces a new resource to be created"
  default     = null
}

variable "assignment_effect" {
  type        = string
  description = "The effect of the set assignment. Useful when the initiative has multiple effects of the same type and 'merge_effects=true'. Omit this to use each definitions default effect or populate individually at 'assignment_parameters'"
  default     = null
}

variable "assignment_parameters" {
  # any: parameter values are defined by each policy's own schema
  type        = any
  description = "The policy assignment parameters. Changing this forces a new resource to be created"
  default     = null
}

variable "assignment_metadata" {
  # any: mirrors Azure Policy free-form assignment metadata
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
  description = "The Azure location where this policy assignment should exist, required when an Identity is assigned. Defaults to West Europe. Changing this forces a new resource to be created"
  default     = "westeurope"
}

variable "non_compliance_messages" {
  type        = map(string)
  description = "The optional non-compliance message(s). Key/Value pairs map as policy_definition_reference_id = 'content', use null = 'content' to specify the Default non-compliance message for all member definitions."
  default     = {}
}

variable "overrides" {
  description = "Optional list of assignment Overrides (preview), max 10. Allows you to change the effect of a policy definition without modifying the underlying policy definition or using a parameterized effect in the policy definition. Selector kind must be one of: policyDefinitionReferenceId, resourceLocation"
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
    condition = alltrue([
      for o in var.overrides : alltrue([
        for s in coalesce(o.selectors, []) :
        contains(["policyDefinitionReferenceId", "resourceLocation"], coalesce(s.kind, "policyDefinitionReferenceId"))
      ])
    ])
    error_message = "Override selector kind must be one of: policyDefinitionReferenceId, resourceLocation."
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
    condition     = length(var.resource_selectors) <= 10
    error_message = "Resource Selectors supports a maximum of 10 entries."
  }
}

variable "identity_ids" {
  type        = list(string)
  description = "Optional list of User Managed Identity IDs which should be assigned to the Policy Initiative"
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
  description = "List of Role definition ID's for the System Assigned Identity. Omit this to use those located in policy definitions. Ignored when using Managed Identities. Changing this forces a new resource to be created"
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
  description = "Member policy effects eligible for automatic remediation tasks. Defaults to [] (remediation is opt-in per #1/#3). Only DeployIfNotExists and Modify can be remediated by Azure Policy."
  default     = []

  validation {
    condition     = length([for e in var.remediate_effects : e if !contains(["DeployIfNotExists", "Modify"], e)]) == 0
    error_message = "Only DeployIfNotExists and Modify effects can be remediated."
  }
}

variable "remediation_reference_ids" {
  type        = list(string)
  description = "Explicit initiative member definition reference ids to remediate when the resolved effect is unresolved (empty). Known non-remediable effects (Audit, Deny, etc.) remain rejected even when explicitly listed. Unknown ids fail the plan. Ignored when empty."
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
  assignment_name_base = try(lower(coalesce(var.assignment_name, var.initiative.name)), "")
  # hash inputs: assignment scope + initiative identity + requested name.
  # Cosmetic inputs (display names/descriptions) deliberately do not affect it.
  assignment_name_hash = substr(md5(jsonencode({
    scope      = var.assignment_scope
    initiative = try(var.initiative.name, "")
    name       = coalesce(var.assignment_name, var.initiative.name)
  })), 0, 8)
  assignment_name = var.collision_resistant_naming ? (
    length(local.assignment_name_base) > 0 ?
    join("-", [substr(local.assignment_name_base, 0, local.assignment_name_trim - 9), local.assignment_name_hash]) :
    ""
  ) : try(lower(substr(coalesce(var.assignment_name, var.initiative.name), 0, local.assignment_name_trim)), "")
  display_name = try(coalesce(var.assignment_display_name, var.initiative.display_name), "")
  description  = try(coalesce(var.assignment_description, var.initiative.description), "")
  # normalize JSON-string input so the boundary jsonencode() never double-encodes (#4)
  assignment_metadata_normalized = var.assignment_metadata == null ? null : try(jsondecode(var.assignment_metadata), var.assignment_metadata)
  _assignment_metadata_json      = local.assignment_metadata_normalized != null ? jsonencode(local.assignment_metadata_normalized) : jsonencode(try(jsondecode(var.initiative.metadata), {}))
  metadata                       = local._assignment_metadata_json

  # convert assignment parameters to the required assignment structure
  parameter_values = var.assignment_parameters != null ? {
    for k, v in var.assignment_parameters :
    k => merge({ value = v })
  } : null

  # merge effect and parameter_values if specified, will use definition default effects if omitted
  parameters = var.assignment_effect != null ? jsonencode(merge(local.parameter_values, { effect = { value = var.assignment_effect } })) : (local.parameter_values != null ? jsonencode(local.parameter_values) : null)

  # determine if a managed identity should be created with this assignment
  identity_type = length(try(coalescelist(var.role_definition_ids, try(var.initiative.role_definition_ids, [])), [])) > 0 ? var.identity_ids != null ? { type = "UserAssigned" } : { type = "SystemAssigned" } : {}

  # try to use policy definition roles if explicit roles are omitted
  role_definition_ids = var.skip_role_assignment == false && length(var.aad_group_remediation_object_ids) == 0 && try(values(local.identity_type)[0], "") == "SystemAssigned" ? try(coalescelist(var.role_definition_ids, try(var.initiative.role_definition_ids, [])), []) : []

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

  # retrieve definition references & create a remediation task for policies with DeployIfNotExists and Modify effects
  # kept as-is: rewriting the != [] comparison risks cty type-semantics drift;
  # behavior is covered by offline tests
  # issue #1/#3: remediation is opt-in and effect-aware. Per-member effective
  # effect comes from the reference parameter_values; explicit
  # remediation_reference_ids override effect resolution per member.
  # issue #62: remediation under DoNotEnforce is Azure-supported (manual
  # remediation of deployIfNotExists works with enforcementMode = DoNotEnforce),
  # so assignment_enforcement_mode no longer gates member exposure to remediation
  # selection. skip_remediation and a viable identity remain required.
  # tflint-ignore: terraform_empty_list_equality
  member_definitions = var.skip_remediation == false && length(local.identity_type) > 0 ? (var.initiative.policy_definition_reference != [] && var.initiative.policy_definition_reference != null ? var.initiative.policy_definition_reference : []) : []
  # issue #1/#3: robust per-member effect resolution for remediation filtering.
  # Member effects appear as literals ("DeployIfNotExists"/"deployIfNotExists")
  # or initiative interpolations "[parameters('effect')]". Interpolations
  # resolve to an explicit assignment_parameters value for that parameter when
  # supplied, else the member parameter defaultValue from the merged initiative
  # schema. Comparison is case-insensitive; unresolvable effects are treated as
  # NOT remediable but stay selectable via explicit remediation_reference_ids.
  initiative_parameters_decoded = try(jsondecode(var.initiative.parameters), var.initiative.parameters, {})
  # issue #62: assignment_effect is an assignment-time value for the initiative's
  # DECLARED "effect" parameter. It is only valid when (a) the initiative
  # declares an "effect" parameter and (b) at least one member reference is
  # actually wired to that initiative-level parameter (parameter_values
  # interpolation "[parameters('effect')]"). Pinned built-ins whose historical
  # schema is intentionally not hydrated declare no effect parameter, so callers
  # must use explicit remediation_reference_ids for unresolved selection instead
  # of pretending an assignment-level effect parameter exists.
  initiative_effect_parameter_declared = contains(keys(local.initiative_parameters_decoded), "effect")
  # issue #65: per-member wiring — assignment_effect may only override a member
  # whose reference is actually wired to the initiative-level effect parameter
  # (parameter_values interpolation "[parameters('effect')]"). Azure passes
  # initiative parameters to specific member parameters through each reference's
  # parameters mapping; an initiative parameter never implicitly replaces every
  # member's effect.
  member_wired_to_initiative_effect = {
    for dr in local.member_definitions :
    dr.reference_id => (
      # issue #65 (Codex P1): the initiative module marks wiring explicitly
      # (rule effect references the parameter). Fall back to the historical
      # parameter_values inference only for external initiative data that does
      # not carry the flag — a required-but-unconsumed effect mapping from that
      # path cannot be distinguished there.
      dr.effect_parameter_wired != null ? dr.effect_parameter_wired :
      try(jsondecode(coalesce(dr.parameter_values, "{}")).effect.value, "") == "[parameters('effect')]"
    )
  }
  # issue #62: unknown assignment_parameters keys are values for parameters the
  # initiative does not declare; Azure rejects such payloads at apply.
  unknown_assignment_parameter_keys = var.assignment_parameters != null ? setsubtract(keys(var.assignment_parameters), keys(local.initiative_parameters_decoded)) : []
  member_raw_effect = {
    for dr in local.member_definitions :
    dr.reference_id => try(jsondecode(coalesce(dr.parameter_values, "{}")).effect.value, "")
  }
  # issue #65: normalized effect source from the policy rule itself, exposed by
  # the initiative module on each reference. This makes literal
  # DeployIfNotExists/Modify rules (which declare no effect parameter, so their
  # reference carries no parameter_values effect entry) visible to remediation
  # auto-detection instead of resolving to an unknown effect.
  member_declared_effect = {
    for dr in local.member_definitions :
    dr.reference_id => try(lower(dr.declared_effect), "")
  }
  member_effect = {
    for dr in local.member_definitions :
    dr.reference_id => lower(
      # issue #65 (Codex P1): when the initiative explicitly marks the member
      # unwired, the rule's literal declared_effect is authoritative — any
      # parameter_values.effect entry is contract satisfaction for a required
      # parameter, not an effect the rule actually consumes.
      dr.effect_parameter_wired == false ? local.member_declared_effect[dr.reference_id] :
      can(regex("^\\[parameters\\('(.+?)'\\)\\]$", local.member_raw_effect[dr.reference_id])) ?
      tostring(try(
        var.assignment_parameters[regex("^\\[parameters\\('(.+?)'\\)\\]$", local.member_raw_effect[dr.reference_id])[0]],
        local.initiative_parameters_decoded[regex("^\\[parameters\\('(.+?)'\\)\\]$", local.member_raw_effect[dr.reference_id])[0]].defaultValue,
        ""
      )) :
      local.member_raw_effect[dr.reference_id] != "" ? local.member_raw_effect[dr.reference_id] :
      local.member_declared_effect[dr.reference_id]
    )
  }
  # issue #65: honor policyEffect assignment overrides. An override REPLACES the
  # effective effect of the references it selects:
  #  - overrides scoped by policyDefinitionReferenceId (in/not_in/absent
  #    selectors) apply to the matching members; the last matching override wins
  #  - an override with NO selectors at all is an unconditional global override
  #    (Azure applies it to every reference); its value is used as-is
  #  - ANY override carrying a resourceLocation selector — alone or mixed with
  #    policyDefinitionReferenceId — is resource-dependent: the effective effect
  #    can differ per remediated resource location, so it is treated as
  #    unresolved (automatic selection suppressed) unless the task's
  #    location_filters prove the override cannot apply to them (every
  #    resourceLocation selector scopes by `in` and none of those locations
  #    intersects location_filters). Explicit remediation_reference_ids remain
  #    the opt-in path.
  override_matches_by_reference = {
    for dr in local.member_definitions :
    dr.reference_id => [
      # Azure ANDs all selectors, so an override whose resourceLocation selector
      # is provably disjoint from the task's location_filters cannot apply to
      # ANY remediated resource — its policyEffect value must not replace the
      # base/member effect even when its referenceId selector matches (#65).
      for idx, o in var.overrides :
      lower(o.value) if !local.override_disjoint_from_location[idx] && (length(coalesce(o.selectors, [])) == 0 || alltrue([
        for s in coalesce(o.selectors, []) :
        coalesce(s.kind, "policyDefinitionReferenceId") != "policyDefinitionReferenceId" || (
          (length(coalesce(s.in, [])) > 0 && contains(coalesce(s.in, []), dr.reference_id))
          || (length(coalesce(s.in, [])) == 0 && length(coalesce(s.not_in, [])) > 0 && !contains(coalesce(s.not_in, []), dr.reference_id))
          || (length(coalesce(s.in, [])) == 0 && length(coalesce(s.not_in, [])) == 0)
        )
      ]))
    ]
  }
  # issue #65: a resourceLocation selector makes an override resource-dependent
  # regardless of its value (remediable or not) and regardless of whether it is
  # mixed with a policyDefinitionReferenceId selector. The ambiguity is waived
  # only when location_filters prove the override cannot touch the remediated
  # resources: location_filters is non-empty AND every resourceLocation selector
  # scopes by `in` AND none of those locations intersects location_filters.
  override_disjoint_from_location = {
    for idx, o in var.overrides : idx => (
      length([
        for s in coalesce(o.selectors, []) :
        s if coalesce(s.kind, "policyDefinitionReferenceId") != "policyDefinitionReferenceId"
      ]) > 0
      && length(var.location_filters) > 0
      && length([
        for s in coalesce(o.selectors, []) :
        s if coalesce(s.kind, "policyDefinitionReferenceId") != "policyDefinitionReferenceId" && (
          length(coalesce(s.in, [])) == 0 || length(setintersection(coalesce(s.in, []), var.location_filters)) > 0
        )
      ]) == 0
    )
  }
  override_is_location_dependent = {
    for idx, o in var.overrides : idx => length([
      for s in coalesce(o.selectors, []) :
      s if coalesce(s.kind, "policyDefinitionReferenceId") != "policyDefinitionReferenceId"
    ]) > 0 && !local.override_disjoint_from_location[idx]
  }
  # an override is location-ambiguous for a member when it selects that member
  # (via referenceId selectors, or globally via no/absent-referenceId selectors)
  # AND carries a resourceLocation selector
  override_location_ambiguous_by_reference = {
    for dr in local.member_definitions :
    dr.reference_id => length([
      for idx, o in var.overrides :
      idx if local.override_is_location_dependent[idx] && (
        length(coalesce(o.selectors, [])) == 0
        || length([
          for s in coalesce(o.selectors, []) :
          s if coalesce(s.kind, "policyDefinitionReferenceId") == "policyDefinitionReferenceId"
        ]) == 0
        || alltrue([
          for s in coalesce(o.selectors, []) :
          coalesce(s.kind, "policyDefinitionReferenceId") != "policyDefinitionReferenceId" || (
            (length(coalesce(s.in, [])) > 0 && contains(coalesce(s.in, []), dr.reference_id))
            || (length(coalesce(s.in, [])) == 0 && length(coalesce(s.not_in, [])) > 0 && !contains(coalesce(s.not_in, []), dr.reference_id))
            || (length(coalesce(s.in, [])) == 0 && length(coalesce(s.not_in, [])) == 0)
          )
        ])
      )
    ]) > 0
  }
  # issue #62/#65: assignment_effect reaches ONLY wired members; unwired members
  # keep their own resolved effect. Overrides take precedence over everything:
  # Azure applies the override regardless of parameter wiring. Location-scoped
  # (resource-dependent) overrides win over even a matching reference-scoped
  # value because the effective effect cannot be proven for a given resource.
  effective_member_effect = {
    for dr in local.member_definitions :
    dr.reference_id => (
      local.override_location_ambiguous_by_reference[dr.reference_id] ? "" :
      length(local.override_matches_by_reference[dr.reference_id]) > 0 ? element(local.override_matches_by_reference[dr.reference_id], length(local.override_matches_by_reference[dr.reference_id]) - 1) :
      var.assignment_effect != null && local.member_wired_to_initiative_effect[dr.reference_id] ? lower(var.assignment_effect) :
      local.member_effect[dr.reference_id]
    )
  }
  # issue #65: per-remediated-member fail-fast. assignment_effect cannot rescue
  # a member that is neither wired to the initiative effect parameter, nor
  # covered by an explicit remediation_reference_id, nor resolvable on its own —
  # such a member would silently produce zero remediation tasks.
  # issue #65 (Codex P1): the fail-fast only applies when automatic remediation
  # selection is actually active for the member. Remediation is opt-in, so an
  # unresolved unwired member with remediate_effects = [] (or with only
  # non-remediable remediate_effects values) is a valid opt-out, not an error;
  # and a policyEffect override that RESOLVES the member (post-override
  # effective effect known) needs no rescue either.
  remediation_auto_selection_active = length([
    for e in var.remediate_effects : e
    if contains(["deployifnotexists", "modify"], lower(e))
  ]) > 0
  assignment_effect_orphan_members = [
    for dr in local.member_definitions : dr.reference_id
    if var.assignment_effect != null
    && contains(["deployifnotexists", "modify"], try(lower(var.assignment_effect), ""))
    && contains([for e in var.remediate_effects : lower(e)], try(lower(var.assignment_effect), ""))
    && local.remediation_auto_selection_active
    && local.effective_member_effect[dr.reference_id] == ""
    && !local.member_wired_to_initiative_effect[dr.reference_id]
    && local.member_effect[dr.reference_id] == ""
    && !contains(var.remediation_reference_ids, dr.reference_id)
  ]
  unknown_remediation_references = (
    length(var.remediation_reference_ids) > 0 && length(setsubtract(var.remediation_reference_ids, [for dr in local.member_definitions : dr.reference_id])) > 0 ?
    file("[ERROR] set_assignment: remediation_reference_ids [${join(", ", setsubtract(var.remediation_reference_ids, [for dr in local.member_definitions : dr.reference_id]))}] are not valid member references. Valid ids: [${join(", ", [for dr in local.member_definitions : dr.reference_id])}].") :
    true
  )
  # Explicit references are an escape hatch only when the effect is unresolved;
  # known effects remain subject to Azure's remediation-safe effect set.
  # assignment_effect overrides per-member effects for this check.
  definitions = local.unknown_remediation_references == true ? [
    for dr in local.member_definitions :
    dr if(
      contains(["deployifnotexists", "modify"], local.effective_member_effect[dr.reference_id]) && (
        contains([for e in var.remediate_effects : lower(e)], local.effective_member_effect[dr.reference_id]) || contains(var.remediation_reference_ids, dr.reference_id)
      )
    ) || (contains(var.remediation_reference_ids, dr.reference_id) && local.effective_member_effect[dr.reference_id] == "")
  ] : []
  definition_reference = {
    mg       = local.remediate.mg > 0 ? local.definitions : []
    sub      = local.remediate.sub > 0 ? local.definitions : []
    rg       = local.remediate.rg > 0 ? local.definitions : []
    resource = local.remediate.resource > 0 ? local.definitions : []
  }

  # evaluate outputs
  assignment = try(
    azurerm_management_group_policy_assignment.set[0],
    azurerm_subscription_policy_assignment.set[0],
    azurerm_resource_group_policy_assignment.set[0],
    azurerm_resource_policy_assignment.set[0],
  {})
  # merge instead of try: for_each resource maps never error, so a try-chain
  # always returns the first (management group) map even at other scopes
  remediation_tasks = merge(
    azurerm_management_group_policy_remediation.rem,
    azurerm_subscription_policy_remediation.rem,
    azurerm_resource_group_policy_remediation.rem,
    azurerm_resource_policy_remediation.rem,
  )
}
