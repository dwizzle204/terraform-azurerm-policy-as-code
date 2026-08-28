variable "definitions" {
  type = map(object({
    source              = optional(string, "custom")
    file_path           = optional(string)
    category            = optional(string)
    policy_name         = optional(string)
    definition_id       = optional(string)
    version             = optional(string)
    parameters          = optional(any)    # optional parameter schema for built-ins (e.g. effect) to be carried into initiative
    policy_rule         = optional(any)    # optional policy rule override for built-ins (e.g. remediation/RBAC metadata)
    mode                = optional(string) # optional mode override for built-ins (e.g. Indexed)
    management_group_id = optional(string) # overrides inherited initiative scope for this definition (#13 review)
    metadata            = optional(any)    # free-form metadata passthrough (e.g. control IDs) (#13 review)
  }))
  default     = {}
  description = "Map of logical definition key -> custom (library/file) or built-in reference. Custom: exactly one of file_path or (category + policy_name). Built-in (source = \"builtin\"): definition_id is required; version is optional where AzureRM supports it. Pinned built-ins (version set) should supply explicit parameters/policy_rule/mode where remediation or mode-specific behavior is needed, as current-version hydration is not used for pinned references."

  validation {
    condition = alltrue([
      for k, v in var.definitions :
      contains(["custom", "builtin"], coalesce(v.source, "custom"))
    ])
    error_message = "definitions[].source must be \"custom\" or \"builtin\"."
  }
  validation {
    condition = alltrue([
      for k, v in var.definitions :
      coalesce(v.source, "custom") == "builtin" ? (
        v.definition_id != null && v.file_path == null && v.category == null && v.policy_name == null
        ) : (
        v.definition_id == null && (v.file_path == null) != (v.category == null || v.policy_name == null)
      )
    ])
    error_message = "Custom definitions require exactly one of file_path or (category + policy_name) and no definition_id; built-in definitions require definition_id and no file_path/category/policy_name."
  }

}

variable "initiatives" {
  type = map(object({
    display_name           = string
    description            = optional(string, "")
    category               = optional(string, "General")
    management_group_id    = optional(string)
    initiative_scope       = optional(string) # "management_group" or "subscription"; explicit when management_group_id is computed (unknown at plan)
    member_definition_keys = list(string)
    metadata               = optional(any) # free-form metadata passthrough (e.g. control IDs) (#13 review)
  }))
  default     = {}
  description = "Map of logical initiative key -> metadata and member definition keys. Members must exist in var.definitions."
  validation {
    condition = alltrue([
      for k, ini in var.initiatives :
      alltrue([for mk in ini.member_definition_keys : contains(keys(var.definitions), mk)])
    ])
    error_message = "initiative member_definition_keys reference unknown definitions: ${join(", ", flatten([for k, ini in var.initiatives : [for mk in ini.member_definition_keys : "${k} -> ${mk}" if !contains(keys(var.definitions), mk)]]))}."
  }

  validation {
    condition = alltrue([
      for k, ini in var.initiatives : ini.initiative_scope == null || try(contains(["management_group", "subscription"], ini.initiative_scope), false)
    ])
    error_message = "initiatives[].initiative_scope must be 'management_group' or 'subscription' when set."
  }

}

variable "assignments" {
  type = map(object({
    initiative_key            = string
    scope                     = string
    assignment_name           = optional(string) # defaults to the logical key when omitted (#13 review)
    enforcement               = optional(bool, true)
    effect                    = optional(string)
    parameters                = optional(any) # any: Azure Policy parameter values are heterogeneous per policy schema (#13 review)
    assignment_location       = optional(string, "westeurope")
    not_scopes                = optional(list(string), [])
    remediate                 = optional(bool, false)
    remediate_effects         = optional(list(string), ["DeployIfNotExists", "Modify"])
    remediation_reference_ids = optional(list(string), [])
    role_definition_ids       = optional(list(string), [])
    metadata                  = optional(any) # free-form metadata passthrough (e.g. control IDs) (#13 review)
  }))
  default     = {}
  description = "Map of logical assignment key -> intent. Scope may be a management group, subscription, resource group or resource id; the correct AzureRM assignment resource is selected automatically. Remediation is opt-in via remediate."
  validation {
    condition = alltrue([
      for k, a in var.assignments : contains(keys(var.initiatives), a.initiative_key)
    ])
    error_message = "assignment initiative_key references unknown initiatives: ${join(", ", [for k, a in var.assignments : "${k} -> ${a.initiative_key}" if !contains(keys(var.initiatives), a.initiative_key)])}."
  }

}

variable "exemptions" {
  type = map(object({
    assignment_key       = string
    scope                = string
    name                 = string
    display_name         = string
    description          = string
    category             = optional(string, "Waiver")
    expires_on           = optional(string)
    policy_reference_ids = optional(list(string), [])
    metadata             = optional(any)
    governed = optional(object({
      owner               = string
      tracking_reference  = string
      reason              = string
      requester           = optional(string)
      approver            = optional(string)
      mitigation          = optional(string)
      governed_created_on = optional(string)
    }))
  }))
  default     = {}
  description = "Map of logical exemption key -> intent. assignment_key must exist in var.assignments."
  validation {
    condition = alltrue([
      for k, e in var.exemptions : contains(keys(var.assignments), e.assignment_key)
    ])
    error_message = "exemption assignment_key references unknown assignments: ${join(", ", [for k, e in var.exemptions : "${k} -> ${e.assignment_key}" if !contains(keys(var.assignments), e.assignment_key)])}."
  }

}
