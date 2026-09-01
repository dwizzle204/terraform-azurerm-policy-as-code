output "definition_ids" {
  description = "Map of all logical definition keys (custom + built-in) -> policy definition id"
  value       = { for k, v in local.all_definitions : k => v.id }
}

output "custom_definition_ids" {
  description = "Map of custom-created definition keys -> policy definition id (subset of definition_ids)"
  value       = { for k, v in module.definitions : k => v.id }
}

output "initiative_ids" {
  description = "Map of initiative key -> policy set definition id"
  value       = { for k, v in module.initiatives : k => v.id }
}

output "assignment_ids" {
  description = "Map of assignment key -> policy assignment id"
  value       = { for k, v in module.assignments : k => v.id }
}

output "assignment_principal_ids" {
  description = "Map of assignment key -> managed identity principal id (when SystemAssigned)"
  value       = { for k, v in module.assignments : k => v.principal_id }
}

output "exemption_ids" {
  description = "Map of exemption key -> policy exemption id"
  value       = { for k, v in module.exemptions : k => v.exemption.id }
}

output "definition_details" {
  description = "Per-definition resolved management-group scope and metadata for all logical definitions (custom + built-in)"
  value       = { for k, v in local.all_definitions : k => { management_group_id = try(v.management_group_id, null), metadata = try(jsondecode(v.metadata), v.metadata) } }
}

output "custom_definition_details" {
  description = "Per-custom-definition details (custom-only, for backwards compatibility)"
  value       = { for k, m in module.definitions : k => { management_group_id = m.definition.management_group_id, metadata = m.metadata } }
}

output "assignment_scopes" {
  description = "Map of logical assignment key -> resolved assignment ARM scope."
  value       = { for k, a in module.assignments : k => a.scope }
}

output "assignment_enforcement" {
  description = "Map of logical assignment key -> resolved enforcement mode."
  value       = { for k, a in module.assignments : k => a.enforcement_mode }
}

output "exemption_scopes" {
  description = "Map of logical exemption key -> resolved exemption scope."
  value       = { for k, e in module.exemptions : k => e.exemption.scope }
}

output "assignment_names" {
  description = "Map of logical assignment key -> resolved Policy Assignment name (defaults to the logical key)"
  value       = { for k, a in module.assignments : k => a.assignment_name }
}

output "assignment_remediation_references" {
  description = "Map of logical assignment key -> member reference IDs selected for remediation"
  value       = { for k, a in module.assignments : k => a.remediation_selected_references }
}

output "assignment_parameters" {
  description = "Map of logical assignment key -> normalized assignment parameters JSON (values for parameters declared by the assigned definition/initiative; issue #62)"
  value       = { for k, a in module.assignments : k => a.parameters }
}
