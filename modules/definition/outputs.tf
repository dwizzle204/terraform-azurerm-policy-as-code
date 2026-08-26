output "id" {
  description = "The Id of the Policy Definition"
  value       = local.definition_id
}

output "name" {
  description = "The name of the Policy Definition"
  value       = var.policy_name
}

output "rules" {
  description = "The rules of the Policy Definition"
  value       = local.policy_rule
}

output "parameters" {
  description = "The parameters of the Policy Definition"
  value       = local.parameters
}

output "metadata" {
  description = "The metadata of the Policy Definition"
  value       = local.metadata
}

output "definition" {
  description = "The combined Policy Definition resource node"
  value = {
    id                  = local.definition_id
    name                = local.policy_name
    display_name        = local.display_name
    description         = local.description
    mode                = local.mode
    management_group_id = var.management_group_id
    metadata            = jsonencode(local.metadata)
    parameters          = jsonencode(local.parameters)
    policy_rule         = jsonencode(local.policy_rule)
  }
}

output "azure_definition_name" {
  description = "The physical Azure Policy Definition resource name (logical-name prefix plus deterministic schema hash suffix, #6)"
  value       = azurerm_policy_definition.def.name
}

output "definition_name_suffix" {
  description = "The deterministic 8-character suffix derived from name, parameter schema and version (#6)"
  value       = local.definition_name_suffix
}
