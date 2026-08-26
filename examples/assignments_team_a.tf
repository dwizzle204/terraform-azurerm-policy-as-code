##################
# General
##################
module "team_a_mg_deny_resource_types" {
  source            = "..//modules/def_assignment"
  definition        = module.deny_resource_types.definition
  assignment_scope  = data.azurerm_management_group.team_a.id
  assignment_effect = "Audit"

  assignment_parameters = {
    listOfResourceTypesNotAllowed = [
      "Microsoft.Storage/operations",
      "Microsoft.Storage/storageAccounts",
      "Microsoft.Storage/storageAccounts/blobServices",
      "Microsoft.Storage/storageAccounts/blobServices/containers",
      "Microsoft.Storage/storageAccounts/listAccountSas",
      "Microsoft.Storage/storageAccounts/listServiceSas",
      "Microsoft.Storage/usages",
    ]
  }
}

##################
# Network
##################
module "team_a_mg_deny_nic_public_ip" {
  source            = "..//modules/def_assignment"
  definition        = module.deny_nic_public_ip.definition
  assignment_scope  = data.azurerm_management_group.team_a.id
  assignment_effect = "Deny"
}

/*
# Staged rollout (SDP) example (#8): gradually enforce the assignment by
# excluding a location first, then flipping the effect once validated.
module "team_a_assignment_staged" {
  source           = "..//modules/set_assignment"
  assignment_scope = data.azurerm_management_group.team_a.id
  initiative       = module.initiative.initiative

  # effect overrides target member definitions by reference id
  overrides = [
    {
      value     = "Disabled"
      selectors = [{ kind = "policyDefinitionReferenceId", in = ["deny_resource_types"] }]
    }
  ]

  resource_selectors = [
    {
      name      = "phase-1-canada"
      selectors = [{ kind = "resourceLocation", in = ["canadacentral", "canadaeast"] }]
    }
  ]
}
*/
