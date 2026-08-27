output "id" {
  description = "The Policy Assignment Id"
  value       = local.assignment.id
}

output "principal_id" {
  description = "The Principal Id of this Policy Assignment's Managed Identity if type is SystemAssigned"
  value       = try(local.assignment.identity[0].principal_id, null)
}

output "remediation_tasks" {
  description = "The Remediation Task Ids and related Policy Definition Ids"
  value = [
    for rem in local.remediation_tasks :
    {
      id                             = rem.id
      policy_definition_reference_id = rem.policy_definition_reference_id
    }
  ]
}

output "definition_references" {
  description = "The Member Definition References"
  value       = try(var.initiative.policy_definition_reference, [])
}

output "definition_reference_ids" {
  description = "The Member Definition Reference Ids"
  value       = try([for ref in var.initiative.policy_definition_reference : ref.reference_id], [])
}

output "assignment_name" {
  description = "The Policy Assignment Name (trimmed to 24 chars at management group scope)"
  value       = local.assignment_name
}

output "parameters" {
  description = "The Parameter Values assigned to this Policy Assignment"
  value       = local.parameters
}

output "remediation_selected_references" {
  description = "The member definition reference IDs selected for remediation after effect filtering and explicit selection"
  value       = [for d in local.definitions : d.reference_id]
}

