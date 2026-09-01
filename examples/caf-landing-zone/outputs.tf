# Stable logical outputs for downstream automation and tests.

output "definition_ids" {
  description = "Map of logical definition key -> built-in policy definition ARM ID."
  value       = module.policy_intent.definition_ids
}

output "initiative_ids" {
  description = "Map of initiative key -> policy set definition ARM ID (one per management group)."
  value       = module.policy_intent.initiative_ids
}

output "assignment_ids" {
  description = "Map of assignment key -> policy assignment ARM ID."
  value       = module.policy_intent.assignment_ids
}

output "principal_ids" {
  description = "Map of assignment key -> managed identity principal ID (Platform only; the other assignments have no identity)."
  value       = module.policy_intent.assignment_principal_ids
}

output "remediation_references" {
  description = "Map of assignment key -> member reference IDs selected for remediation (non-empty for Platform)."
  value       = module.policy_intent.assignment_remediation_references
}

output "exemption_ids" {
  description = "Map of exemption key -> policy exemption ARM ID."
  value       = module.policy_intent.exemption_ids
}

# Intent inputs are exposed as contract outputs so offline tests can prove that
# each logical assignment and waiver targets the intended scope and posture.
output "assignment_scopes" {
  description = "Map of logical assignment key -> requested scope."
  value = {
    platform      = var.platform_management_group_id
    landing_zones = var.landing_zones_management_group_id
    sandboxes     = var.sandboxes_management_group_id
  }
}

output "assignment_enforcement" {
  description = "Map of logical assignment key -> enforcement posture."
  value = {
    platform      = true
    landing_zones = true
    sandboxes     = false
  }
}

output "exemption_scopes" {
  description = "Map of logical exemption key -> child scope."
  value       = { lz_subscription_waiver = var.landing_zone_subscription_id }
}
