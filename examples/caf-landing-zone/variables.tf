# CAF Landing Zone example inputs.
#
# All identifiers must be full ARM resource IDs - this framework assigns and
# exempts against existing Azure resources; it never creates management groups.

variable "platform_management_group_id" {
  description = "Full ARM resource ID of the Platform management group (shared platform services). Example: /providers/Microsoft.Management/managementGroups/contoso-platform"
  type        = string
}

variable "landing_zones_management_group_id" {
  description = "Full ARM resource ID of the Landing zones management group (workload guardrails). Example: /providers/Microsoft.Management/managementGroups/contoso-landing-zones"
  type        = string
}

variable "sandboxes_management_group_id" {
  description = "Full ARM resource ID of the Sandboxes management group (permissive experimentation, still governed). Example: /providers/Microsoft.Management/managementGroups/contoso-sandboxes"
  type        = string
}

variable "landing_zone_subscription_id" {
  description = "Full ARM resource ID of one workload subscription under the Landing zones management group. Used to demonstrate a child-scope exemption against a parent-MG assignment. Example: /subscriptions/00000000-0000-0000-0000-000000000000"
  type        = string
}

variable "governed_waiver_expires_on" {
  description = "Expiry date for the governed waiver; must be strictly later than the plan date (YYYY-MM-DD)."
  type        = string
}
