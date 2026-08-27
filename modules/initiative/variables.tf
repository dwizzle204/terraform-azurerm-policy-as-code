variable "management_group_id" {
  type        = string
  description = "The management group scope at which the initiative will be defined. Defaults to current Subscription if omitted. Changing this forces a new resource to be created. Note: if you are using azurerm_management_group to assign a value to management_group_id, be sure to use name or group_id attribute, but not id. When creating a management group and its initiative in the same configuration, set var.initiative_scope = \"management_group\" explicitly so the resource count is known at plan time."
  default     = null
}

variable "initiative_scope" {
  type        = string
  description = "Scope type for the initiative. Valid values are 'management_group' and 'subscription'. When null (default), scope is inferred from management_group_id. Set explicitly when management_group_id is computed (unknown at plan time)."
  default     = null

  validation {
    condition     = var.initiative_scope == null || contains(["management_group", "subscription"], var.initiative_scope)
    error_message = "initiative_scope must be 'management_group' or 'subscription' when set."
  }
}

variable "initiative_name" {
  type        = string
  description = "Policy initiative name. Changing this forces a new resource to be created"

  validation {
    condition     = length(var.initiative_name) <= 64
    error_message = "Initiative names have a maximum 64 character limit."
  }
}

variable "initiative_display_name" {
  type        = string
  description = "Policy initiative display name"

  validation {
    condition     = length(var.initiative_display_name) <= 128
    error_message = "Initiative display names have a maximum 128 character limit."
  }
}

variable "initiative_description" {
  type        = string
  description = "Policy initiative description"
  default     = ""

  validation {
    condition     = length(var.initiative_description) <= 512
    error_message = "Initiative descriptions have a maximum 512 character limit."
  }
}

variable "initiative_category" {
  type        = string
  description = "The category of the initiative"
  default     = "General"
}

variable "initiative_version" {
  type        = string
  description = "The version for this initiative, defaults to 1.0.0"
  default     = "1.0.0"
}

variable "member_definitions" {
  description = "Policy Definition resource nodes that will be members of this initiative (matches the definition module's `definition` output)"
  type = list(object({
    id                  = string
    name                = string
    display_name        = optional(string)
    description         = optional(string)
    mode                = optional(string)
    management_group_id = optional(string)
    metadata            = optional(string)
    parameters          = optional(string)
    policy_rule         = optional(string)
    version             = optional(string)
  }))
}

variable "initiative_metadata" {
  # any: mirrors Azure Policy free-form metadata
  type        = any
  description = "The metadata for the policy initiative. This is a JSON object representing additional metadata that should be stored with the policy initiative. Omitting this will default to merge var.initiative_category and var.initiative_version"
  default     = null

  validation {
    condition     = var.initiative_metadata == null || can({ for k, v in var.initiative_metadata : k => v }) || can(tostring(var.initiative_metadata))
    error_message = "initiative_metadata must be an object or a JSON-encoded string."
  }
}

variable "merge_effects" {
  type        = bool
  description = "Should the module merge all member definition effects? Defaults to true"
  default     = true
}

variable "merge_parameters" {
  type        = bool
  description = "Should the module merge all member definition parameters? Defaults to true"
  default     = true
}

variable "duplicate_members" {
  type        = bool
  description = "Does the Initiative contain duplicate member definitions? Defaults to false"
  default     = false
}

variable "camel_case_references" {
  type        = bool
  description = "Should definition references be converted to Camel Case for readability? Defaults to false"
  default     = false
}

variable "use_display_name_for_references" {
  type        = bool
  description = "Should definition references take policy display_name in favour of policy_name? Defaults to false"
  default     = false
}

locals {
  # collate all definition properties into a single reusable object:
  # - index numbers (idx) will be prefixed to references when using duplicate member definitions
  member_properties = {
    for idx, d in var.member_definitions :
    var.duplicate_members == false ? d.name : "${idx}_${d.name}" => {
      id   = d.id
      mode = try(d.mode, "")
      reference = var.duplicate_members == false ? (
        var.use_display_name_for_references == false ? d.name : coalesce(d.display_name, d.name)
        ) : (
        var.use_display_name_for_references == false ? "${idx}_${d.name}" : "${idx}_${coalesce(d.display_name, d.name)}"
      )
      parameters = try(jsondecode(d.parameters), {})
      category   = try(jsondecode(d.metadata).category, "")
      # optional attrs yield null (not an error) once member_definitions is
      # fully typed, so null-guard instead of relying on try() fallthrough
      version = replace(d.version != null ? d.version : try(jsondecode(d.metadata).version, "1.*"), "/^([0-9]+\\.[0-9]+)\\.[0-9]+(-preview)?$/", "$1.*$2")
      non_compliance_message = coalesce(
        try(jsondecode(d.metadata).non_compliance_message, null),
        d.description, d.display_name,
        "Flagged by Policy: ${d.name}"
      )
      role_definition_ids = try(jsondecode(d.policy_rule).then.details.roleDefinitionIds, [])
    }
  }

  # shift the dynamic 'policy_definition_reference' block to locals so that params can be created and exported without waiting for resource to deploy
  # useful as a dependency for assignment modules
  policy_definition_reference = {
    for k, v in local.member_properties :
    k => {
      policy_definition_id = v.id
      reference_id         = var.camel_case_references == false ? v.reference : replace(title(replace(v.reference, "/-|_|\\s/", " ")), "/\\s/", "")
      version              = v.version
      parameter_values = length(v.parameters) > 0 ? jsonencode({
        for i in keys(v.parameters) :
        i => {
          value = i == "effect" && var.merge_effects == false ? "[parameters('${i}_${v.reference}')]" : var.merge_parameters == false ? "[parameters('${i}_${v.reference}')]" : "[parameters('${i}')]"
        }
      }) : null
    }
  }

  # issue #7: detect duplicate parameter names declared by multiple members.
  # Canonicalization via jsonencode normalizes key order, so byte-identical
  # schemas merge safely while genuinely different schemas are conflicts.
  parameter_declarations = {
    for entry in flatten([
      for definition, properties in local.member_properties :
      [
        for parameter_name, schema in properties.parameters :
        {
          parameter_name = parameter_name
          member         = definition
          canonical      = jsonencode(schema)
        }
      ]
    ]) :
    entry.parameter_name => entry...
  }

  conflicting_parameters = {
    for parameter_name, declarations in local.parameter_declarations :
    parameter_name => [for d in declarations : d.member]
    if length(declarations) > 1 && (var.merge_effects == true || parameter_name != "effect") && length(distinct([for d in declarations : d.canonical])) > 1
  }

  # combine all discovered definition parameters using interpolation
  parameters_raw = merge(values({
    for definition, properties in local.member_properties :
    definition => {
      for parameter_name, parameter_value in properties.parameters :
      # if do not merge parameters (or only effects) then suffix parameters with definition references
      var.merge_parameters == false || parameter_name == "effect" && var.merge_effects == false ?
      "${parameter_name}_${properties.reference}" :

      parameter_name => {
        for k, v in parameter_value :
        k => (
          # if do not merge parameters (or only effects) then suffix displayNames with definition references
          k == "metadata" && var.merge_parameters == false || var.merge_effects == false && try(v.displayName, "") == "Effect" ?
          merge(v, { displayName = "${v.displayName} For Policy: ${properties.reference}" }) :
          v
        )
      }
    }
  })...)

  # fail fast on incompatible duplicate parameter schemas when merging (#7).
  # Both branches are JSON strings so the conditional passes cty unification;
  # the file() sentinel raises a descriptive plan-time diagnostic naming every
  # conflicting parameter and its declaring members.
  parameters = jsondecode(
    var.merge_parameters != true || length(local.conflicting_parameters) == 0 ?
    jsonencode(local.parameters_raw) :
    file("[ERROR] Initiative '${var.initiative_name}' has conflicting parameter schemas across member definitions: ${join("; ", [for p, members in local.conflicting_parameters : "${p}: [${join(", ", members)}]"])}. Set merge_parameters=false and supply explicit parameter mapping, or align the member schemas.")
  )

  # generate replacement trigger by hashing parameters, included as an output to prevent regen at assignment
  replace_trigger = md5(jsonencode(local.parameters))

  # combine all role definition IDs present in the policyRule
  all_role_definition_ids = try(distinct([for v in flatten(values({
    for k, v in local.member_properties :
    k => v.role_definition_ids
  })) : lower(v)]), [])

  # normalize JSON-string input so the resource boundary jsonencode() never
  # double-encodes (#4)
  metadata = try(jsondecode(coalesce(null, var.initiative_metadata, merge({ category = var.initiative_category }, { version = var.initiative_version }))), coalesce(null, var.initiative_metadata, merge({ category = var.initiative_category }, { version = var.initiative_version })))

  # build non-compliance messages from metadata, or default to description/display_name if not present
  non_compliance_messages = merge(
    { null = "Flagged by Initiative: ${var.initiative_name}" }, # default non-compliance message
    { for k, v in local.member_properties :
      var.camel_case_references == false ? v.reference : replace(title(replace(v.reference, "/-|_|\\s/", " ")), "/\\s/", "") => v.non_compliance_message
      if contains(["All", "Indexed"], v.mode) && var.duplicate_members == false # messages fail on other modes
    }
  )

  initiative_id = local.is_management_group_scope ? "${var.management_group_id}/providers/Microsoft.Authorization/policySetDefinitions/${var.initiative_name}" : "${data.azurerm_subscription.current.id}/providers/Microsoft.Authorization/policySetDefinitions/${var.initiative_name}"
}
