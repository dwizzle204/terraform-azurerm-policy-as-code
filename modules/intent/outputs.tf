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
