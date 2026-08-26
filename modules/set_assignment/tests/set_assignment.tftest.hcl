mock_provider "azurerm" {
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/preview/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
  mock_resource "azurerm_resource_group_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
  mock_resource "azurerm_resource_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1/providers/Microsoft.Compute/virtualMachines/vm-1/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
}

mock_provider "azuread" {}

variables {
  assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  initiative = {
    id                          = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mock_initiative"
    name                        = "mock_initiative"
    display_name                = "Mock Initiative"
    description                 = "Mock"
    management_group_id         = null
    parameters                  = {}
    metadata                    = jsonencode({ category = "Mock" })
    role_definition_ids         = []
    replace_trigger             = "abc"
    policy_definition_reference = []
  }
}

run "subscription_scope_selects_subscription_assignment" {
  command = plan

  assert {
    condition     = output.id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_initiative"
    error_message = "A subscription scope must create the subscription-scoped assignment resource"
  }
}

run "management_group_scope_selects_mg_assignment_and_trims_name" {
  command = plan

  variables {
    assignment_scope = "/providers/Microsoft.Management/managementGroups/preview"
    initiative       = merge(var.initiative, { name = "this_initiative_name_is_longer_than_twenty_four" })
  }

  assert {
    condition     = startswith(output.id, "/providers/Microsoft.Management/managementGroups/")
    error_message = "An MG scope must create the MG-scoped assignment resource"
  }

  assert {
    condition     = output.assignment_name == "this_initiative_name_is_" && length(output.assignment_name) == 24
    error_message = "Assignment names at MG scope must be lowercased and trimmed to 24 chars"
  }
}

run "resource_group_scope_selects_rg_assignment" {
  command = plan

  variables {
    assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1"
  }

  assert {
    condition     = endswith(output.id, "resourceGroups/rg-1/providers/Microsoft.Authorization/policyAssignments/mock_initiative")
    error_message = "An RG scope must create the RG-scoped assignment resource"
  }
}

run "no_identity_means_no_remediation_or_principal" {
  command = plan

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "Remediation tasks require a managed identity"
  }

  assert {
    condition     = output.principal_id == null
    error_message = "No managed identity means no principal id"
  }
}

run "identity_and_dine_reference_creates_remediation" {
  command = plan

  variables {
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1
    error_message = "A DINE member with SystemAssigned identity should produce one remediation task"
  }

  assert {
    condition     = output.remediation_tasks[0].policy_definition_reference_id == "dine_member"
    error_message = "Remediation task must reference the DINE member definition"
  }
}

run "skip_remediation_suppresses_remediation_tasks" {
  command = plan

  variables {
    skip_remediation    = true
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member", reference_id = "dine_member", parameter_values = jsonencode({}) }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "skip_remediation=true must suppress remediation tasks"
  }
}

run "assignment_effect_is_merged_into_parameters" {
  command = plan

  variables {
    assignment_effect     = "Audit"
    assignment_parameters = { retentionDays = 90 }
  }

  assert {
    condition     = jsondecode(output.parameters)["effect"].value == "Audit" && jsondecode(output.parameters)["retentionDays"].value == 90
    error_message = "assignment_effect must merge into parameter values alongside explicit parameters"
  }
}

run "resource_scope_selects_resource_assignment" {
  command = plan

  variables {
    assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1/providers/Microsoft.Compute/virtualMachines/vm-1"
  }

  assert {
    condition     = endswith(output.id, "virtualMachines/vm-1/providers/Microsoft.Authorization/policyAssignments/mock_initiative")
    error_message = "A resource scope must create the resource-scoped assignment resource"
  }
}

run "remediation_tasks_are_not_effect_filtered_upstream" {
  # documents current upstream behavior: remediation tasks are gated on
  # enforcement mode + managed identity, NOT on the member effect. A member
  # with a plain Audit effect still receives a remediation task.
  command = plan

  variables {
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/audit_member"
          reference_id         = "audit_member"
          parameter_values     = jsonencode({ effect = { value = "Audit" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "audit_member"
    error_message = "Documents upstream behavior: even Audit-effect members get remediation tasks when identity is present"
  }
}
