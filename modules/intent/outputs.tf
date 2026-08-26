output "definition_ids" {
  description = "Map of definition key -> policy definition id"
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
  description = "Per-definition resolved management-group scope and metadata (useful for asserting catalog/control metadata forwarding)"
  value       = { for k, m in module.definitions : k => { management_group_id = m.definition.management_group_id, metadata = m.metadata } }
}

output "assignment_names" {
  description = "Map of logical assignment key -> resolved Policy Assignment name (defaults to the logical key)"
  value       = { for k, a in module.assignments : k => a.assignment_name }
}

output "assignment_remediation_references" {
  description = "Map of logical assignment key -> member reference IDs selected for remediation"
  value       = { for k, a in module.assignments : k => a.remediation_selected_references }
}
