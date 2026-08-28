variable "name" {
  type        = string
  description = "Name for the Policy Exemption"

  validation {
    condition     = length(var.name) <= 64
    error_message = "Exemption names have a maximum 64 character limit."
  }
}

variable "display_name" {
  type        = string
  description = "Display name for the Policy Exemption"

  validation {
    condition     = length(var.display_name) <= 128
    error_message = "Exemption display names have a maximum 128 character limit."
  }
}

variable "description" {
  type        = string
  description = "Description for the Policy Exemption"

  validation {
    condition     = length(var.description) <= 512
    error_message = "Exemption descriptions have a maximum 512 character limit."
  }
}

variable "scope" {
  type        = string
  description = "Scope for the Policy Exemption"

  validation {
    condition     = can(regex("(?i)^(?:/providers/Microsoft\\.Management/managementGroups/[^/]+|/subscriptions/[^/]+(?:/resourceGroups/[^/]+(?:/providers/.+)?|/providers/.+)?)$", var.scope))
    error_message = "scope must be a valid Azure scope: management group, subscription, resource group, or resource."
  }
}

variable "policy_assignment_id" {
  type        = string
  description = "The ID of the policy assignment that is being exempted"
}

variable "policy_definition_reference_ids" {
  type        = list(string)
  description = "The optional policy definition reference ID list when the associated policy assignment is an assignment of a policy set definition. Omit to exempt all member definitions"
  default     = []
}

variable "camel_case_references" {
  type        = bool
  description = "Should definition references be converted to Camel Case for readability? Defaults to false"
  default     = false
}

variable "exemption_category" {
  type        = string
  description = "The policy exemption category. Possible values are Waiver or Mitigated. Defaults to Waiver"
  default     = "Waiver"

  validation {
    condition     = var.exemption_category == "Waiver" || var.exemption_category == "Mitigated"
    error_message = "Exemption category possible values are: Waiver or Mitigated."
  }
}

variable "expires_on" {
  type        = string
  description = "Optional expiration date (format yyyy-mm-dd) of the policy exemption. Defaults to no expiry"
  default     = null

  validation {
    condition = (
      var.expires_on == null ? true :
      can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.expires_on)) ? (
        tonumber(regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on)[1]) >= 1 && tonumber(regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on)[1]) <= 12 &&
        tonumber(regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on)[2]) >= 1 && tonumber(regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on)[2]) <= (
          contains(["01", "03", "05", "07", "08", "10", "12"], regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on)[1]) ? 31 :
          contains(["04", "06", "09", "11"], regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on)[1]) ? 30 :
          (tonumber(regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on)[0]) % 4 == 0 && (tonumber(regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on)[0]) % 100 != 0 || tonumber(regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on)[0]) % 400 == 0)) ? 29 : 28
        )
      ) : false
    )
    error_message = "expires_on must be a valid calendar date in format yyyy-mm-dd (e.g. 2026-02-30 is invalid)."
  }

  validation {
    condition = (
      var.governed == null ? true :
      var.exemption_category != "Waiver" ? true :
      var.expires_on == null ? true :
      try(timecmp("${var.expires_on}T00:00:00Z", plantimestamp()) > 0, false)
    )
    error_message = "Governed Waiver expires_on must be a future date strictly after the plan date (today fails)."
  }
}

variable "metadata" {
  # any: mirrors Azure Policy free-form exemption metadata
  type        = any
  description = "Optional policy exemption metadata. For example but not limited to; requestedBy, approvedBy, approvedOn, ticketRef, etc"
  default     = null

  validation {
    condition     = var.metadata == null || (can({ for k, v in var.metadata : k => v }) && !can(tolist(var.metadata))) || try(can({ for k, v in jsondecode(var.metadata) : k => v }) && !can(tolist(jsondecode(var.metadata))), false)
    error_message = "metadata must be an object or a JSON-encoded string."
  }
}

variable "governed" {
  type = object({
    owner               = string
    requester           = optional(string)
    approver            = optional(string)
    tracking_reference  = string
    reason              = string
    mitigation          = optional(string)
    governed_created_on = optional(string)
  })
  default     = null
  description = "Optional governance contract (#10). When set: Waiver exemptions REQUIRE expires_on; Mitigated exemptions REQUIRE mitigation; governed_created_on (yyyy-mm-dd) is persisted in metadata when provided. Omit for simple exemptions (behavior unchanged)."
}

locals {
  exemption_scope = try({
    mg       = length(regexall("(?i)(/managementGroups/)", var.scope)) > 0 ? 1 : 0,
    sub      = length(split("/", var.scope)) == 3 ? 1 : 0,
    rg       = length(regexall("(?i)(/managementGroups/)", var.scope)) < 1 ? length(split("/", var.scope)) == 5 ? 1 : 0 : 0,
    resource = length(split("/", var.scope)) >= 6 ? 1 : 0,
  })

  expires_on = var.expires_on != null ? "${var.expires_on}T23:00:00Z" : null

  # governance contract checks (#10): evaluating these locals raises a
  # descriptive sentinel error when the governed contract is violated.
  # Governed waivers must expire strictly after the plan date (today fails);
  # comparison uses plantimestamp() for deterministic plan-time validation.
  # strict calendar validation (leap years included); regex alone accepts e.g. 2026-99-40 (#10 review)
  expires_on_date_parts = var.expires_on != null ? regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.expires_on) : ["0000", "00", "00"]
  expires_on_days_in_month = (
    contains(["01", "03", "05", "07", "08", "10", "12"], local.expires_on_date_parts[1]) ? 31 :
    contains(["04", "06", "09", "11"], local.expires_on_date_parts[1]) ? 30 :
    (tonumber(local.expires_on_date_parts[0]) % 4 == 0 && (tonumber(local.expires_on_date_parts[0]) % 100 != 0 || tonumber(local.expires_on_date_parts[0]) % 400 == 0)) ? 29 : 28
  )
  expires_on_is_valid_calendar_date = (
    can(regex("^\\d{4}-\\d{2}-\\d{2}$", coalesce(var.expires_on, "1970-01-01"))) &&
    tonumber(local.expires_on_date_parts[1]) >= 1 && tonumber(local.expires_on_date_parts[1]) <= 12 &&
    tonumber(local.expires_on_date_parts[2]) >= 1 && tonumber(local.expires_on_date_parts[2]) <= local.expires_on_days_in_month
  )
  governed_created_on_date_parts = try(regex("^(\\d{4})-(\\d{2})-(\\d{2})$", var.governed.governed_created_on), ["0000", "00", "00"])
  governed_created_on_days_in_month = (
    contains(["01", "03", "05", "07", "08", "10", "12"], local.governed_created_on_date_parts[1]) ? 31 :
    contains(["04", "06", "09", "11"], local.governed_created_on_date_parts[1]) ? 30 :
    (tonumber(local.governed_created_on_date_parts[0]) % 4 == 0 && (tonumber(local.governed_created_on_date_parts[0]) % 100 != 0 || tonumber(local.governed_created_on_date_parts[0]) % 400 == 0)) ? 29 : 28
  )
  governed_created_on_is_valid = var.governed == null || try(var.governed.governed_created_on, null) == null || (
    can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.governed.governed_created_on)) &&
    tonumber(local.governed_created_on_date_parts[1]) >= 1 && tonumber(local.governed_created_on_date_parts[1]) <= 12 &&
    tonumber(local.governed_created_on_date_parts[2]) >= 1 && tonumber(local.governed_created_on_date_parts[2]) <= local.governed_created_on_days_in_month
  )

  # governed waivers must expire strictly after the plan date (today fails)
  expires_on_is_future = (
    var.expires_on != null && local.expires_on_is_valid_calendar_date ?
    timecmp("${var.expires_on}T00:00:00Z", plantimestamp()) > 0 : false
  )

  governance_checks = (
    var.governed == null ? "ok" :
    var.exemption_category == "Waiver" && var.expires_on == null ?
    file("[ERROR] Governed Waiver exemptions require expires_on (yyyy-mm-dd). Set expires_on or change exemption_category.") :
    var.exemption_category == "Mitigated" && try(var.governed.mitigation, null) == null ?
    file("[ERROR] Governed Mitigated exemptions require governed.mitigation describing the remediation in place.") :
    var.expires_on != null && !local.expires_on_is_valid_calendar_date ?
    file("[ERROR] expires_on must be a valid calendar date in format yyyy-mm-dd (e.g. 2026-12-31).") :
    !local.governed_created_on_is_valid ?
    file("[ERROR] governed.governed_created_on must be a valid calendar date in format yyyy-mm-dd (e.g. 2026-12-31).") :
    var.governed != null && var.exemption_category == "Waiver" && !local.expires_on_is_future ?
    file("[ERROR] Governed Waiver expires_on must be a future date strictly after the plan date (got '${coalesce(var.expires_on, "")}', plan date '${formatdate("YYYY-MM-DD", plantimestamp())}').") :
    "ok"
  )

  governance_metadata = var.governed != null ? merge({
    owner             = var.governed.owner
    requester         = try(var.governed.requester, null)
    approver          = try(var.governed.approver, null)
    trackingReference = var.governed.tracking_reference
    reason            = var.governed.reason
    mitigation        = try(var.governed.mitigation, null)
  }, try(var.governed.governed_created_on, null) != null ? { created = var.governed.governed_created_on } : {}) : null

  # string-form user metadata is decoded before merging so it is not silently
  # dropped when the governance contract is active (#10 review follow-up)
  metadata = local.governance_checks == "ok" ? (
    var.governed != null ?
    jsonencode(merge(local.user_metadata_decoded, local.governance_metadata)) :
    (var.metadata != null ? jsonencode(var.metadata) : null)
  ) : "{}"

  user_metadata_decoded = try(jsondecode(coalesce(null, var.metadata, "{}")), { for k, v in var.metadata : k => v })

  # generate reference Ids when unknown, assumes the set was created with the initiative module
  policy_definition_reference_ids = var.camel_case_references == true ? [for name in var.policy_definition_reference_ids :
    replace(title(replace(name, "/-|_|\\s/", " ")), "/\\s/", "")
  ] : var.policy_definition_reference_ids

  exemption_id = try(
    azurerm_management_group_policy_exemption.management_group_exemption[0].id,
    azurerm_subscription_policy_exemption.subscription_exemption[0].id,
    azurerm_resource_group_policy_exemption.resource_group_exemption[0].id,
    azurerm_resource_policy_exemption.resource_exemption[0].id,
  "")
}
