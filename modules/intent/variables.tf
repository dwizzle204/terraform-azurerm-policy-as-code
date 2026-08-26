variable "definitions" {
  type = map(object({
    file_path   = optional(string)
    category    = optional(string)
    policy_name = optional(string)
  }))
  default     = {}
  description = "Map of logical definition key -> library lookup. Exactly one of file_path or (category + policy_name) per entry."
  validation {
    condition = alltrue([
      for k, v in var.definitions :
      (v.file_path == null) != (v.category == null && v.policy_name == null)
    ])
    error_message = "Each definitions entry must set exactly one of file_path or (category + policy_name)."
  }

}

variable "initiatives" {
  type = map(object({
    display_name           = string
    description            = optional(string, "")
    category               = optional(string, "General")
    management_group_id    = optional(string)
    member_definition_keys = list(string)
  }))
  default     = {}
  description = "Map of logical initiative key -> metadata and member definition keys. Members must exist in var.definitions."
  validation {
    condition = alltrue([
      for k, ini in var.initiatives :
      alltrue([for mk in ini.member_definition_keys : contains(keys(var.definitions), mk)])
    ])
    error_message = "initiative member_definition_keys reference unknown definitions."
  }

}

variable "assignments" {
  type = map(object({
    initiative_key      = string
    scope               = string
    assignment_name     = optional(string)
    enforcement         = optional(bool, true)
    effect              = optional(string)
    parameters          = optional(map(any))
    assignment_location = optional(string, "westeurope")
    not_scopes          = optional(list(string), [])
    remediate           = optional(bool, true)
    role_definition_ids = optional(list(string), [])
  }))
  default     = {}
  description = "Map of logical assignment key -> intent. Scope may be a management group, subscription, resource group or resource id; the correct AzureRM assignment resource is selected automatically."
  validation {
    condition = alltrue([
      for k, a in var.assignments : contains(keys(var.initiatives), a.initiative_key)
    ])
    error_message = "assignment initiative_key references unknown initiatives."
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
    governed = optional(object({
      owner              = string
      tracking_reference = string
      reason             = string
      requester          = optional(string)
      approver           = optional(string)
      mitigation         = optional(string)
    }))
  }))
  default     = {}
  description = "Map of logical exemption key -> intent. assignment_key must exist in var.assignments."
  validation {
    condition = alltrue([
      for k, e in var.exemptions : contains(keys(var.assignments), e.assignment_key)
    ])
    error_message = "exemption assignment_key references unknown assignments."
  }

}
