mock_provider "azurerm" {
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/preview/providers/Microsoft.Authorization/policyAssignments/mock_definition" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_definition" }
    override_during = plan
  }
  mock_resource "azurerm_resource_group_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1/providers/Microsoft.Authorization/policyAssignments/mock_definition" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_remediation" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.PolicyInsights/remediations/mock_definition" }
    override_during = plan
  }
}

mock_provider "azuread" {}

variables {
  assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  definition = {
    id                  = "/providers/Microsoft.Authorization/policyDefinitions/mock_definition"
    name                = "mock_definition_name_exceeding_twentyfour_chars"
    display_name        = "Mock Definition"
    description         = "Mock"
    mode                = "All"
    management_group_id = null
    metadata            = jsonencode({ category = "Mock" })
    parameters          = jsonencode({})
    policy_rule         = jsonencode({ if = {}, then = {} })
  }
}

run "subscription_scope_selects_subscription_assignment" {
  command = plan

  assert {
    condition     = output.id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_definition"
    error_message = "Subscription scope must select the subscription assignment resource"
  }
}

run "mg_scope_trims_assignment_name_to_24_chars" {
  command = plan

  variables {
    assignment_scope = "/providers/Microsoft.Management/managementGroups/preview"
  }

  assert {
    condition     = startswith(output.id, "/providers/Microsoft.Management/managementGroups/")
    error_message = "MG scope must select the MG assignment resource"
  }

  assert {
    condition     = output.assignment_name == "mock_definition_name_exc" && length(output.assignment_name) == 24
    error_message = "MG scoped names must be lowercased and trim to 24 chars"
  }
}

run "explicit_role_definitions_pass_through" {
  command = plan

  variables {
    role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
  }

  assert {
    condition     = length(output.role_definition_ids) == 1 && contains(output.role_definition_ids, "/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c")
    error_message = "Explicit role definitions must pass through unchanged"
  }
}

run "role_definitions_from_policy_rule_are_discovered" {
  command = plan

  variables {
    definition = merge(var.definition, {
      policy_rule = jsonencode({
        if   = {}
        then = { details = { roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"] } }
      })
    })
  }

  assert {
    condition     = length(output.role_definition_ids) == 1
    error_message = "Role definitions embedded in the policy rule should drive identity and role assignment without explicit inputs"
  }
}

run "skip_remediation_removes_remediation_task" {
  command = plan

  variables {
    skip_remediation    = true
    role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
  }

  assert {
    condition     = output.remediation_id == ""
    error_message = "skip_remediation must prevent remediation task creation"
  }
}

run "identity_and_remediation_enabled_creates_task" {
  command = plan

  variables {
    role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
  }

  assert {
    condition     = output.remediation_id != ""
    error_message = "DINE-capable identity assignment should create a remediation task"
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
