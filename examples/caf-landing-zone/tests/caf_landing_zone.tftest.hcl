mock_provider "azurerm" {
  mock_data "azurerm_policy_definition_built_in" {
    defaults = {
      id                  = "/providers/Microsoft.Authorization/policyDefinitions/caf-built-in"
      name                = "caf-built-in"
      display_name        = "CAF built-in policy"
      description         = "Mocked Microsoft built-in"
      mode                = "Indexed"
      management_group_id = null
      metadata            = "{\"category\":\"General\",\"version\":\"3.0.0\"}"
      parameters          = "{\"effect\":{\"type\":\"String\",\"defaultValue\":\"DeployIfNotExists\"},\"listOfAllowedLocations\":{\"type\":\"Array\"}}"
      policy_rule         = "{\"if\":{\"field\":\"type\",\"equals\":\"Microsoft.Network/virtualNetworks\"},\"then\":{\"effect\":\"[parameters('effect')]\",\"details\":{\"roleDefinitionIds\":[\"/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c\"]}}}"
      version             = "3.0.0"
      policy_type         = "BuiltIn"
    }
    override_during = plan
  }
  mock_resource "azurerm_management_group_policy_set_definition" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/mock/providers/Microsoft.Authorization/policySetDefinitions/mock" }
    override_during = plan
  }
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/mock/providers/Microsoft.Authorization/policyAssignments/mock" }
    override_during = plan
  }
  mock_resource "azurerm_management_group_policy_exemption" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/mock/providers/Microsoft.Authorization/policyExemptions/mock" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_exemption" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyExemptions/mock" }
    override_during = plan
  }
  mock_resource "azurerm_role_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleAssignments/mock" }
    override_during = plan
  }
  mock_resource "azurerm_user_assigned_identity" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock", principal_id = "00000000-0000-0000-0000-000000000001", client_id = "00000000-0000-0000-0000-000000000002" }
    override_during = plan
  }
  mock_resource "azurerm_management_group_policy_remediation" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/mock/providers/Microsoft.PolicyInsights/remediations/mock" }
    override_during = plan
  }
}

mock_provider "azuread" {}

variables {
  platform_management_group_id      = "/providers/Microsoft.Management/managementGroups/platform"
  landing_zones_management_group_id = "/providers/Microsoft.Management/managementGroups/landing-zones"
  sandboxes_management_group_id     = "/providers/Microsoft.Management/managementGroups/sandboxes"
  landing_zone_subscription_id      = "/subscriptions/11111111-1111-1111-1111-111111111111"
}

run "caf_scopes_and_rollout_are_distinct" {
  command = plan
  assert {
    condition     = output.assignment_scopes.platform == var.platform_management_group_id && output.assignment_scopes.landing_zones == var.landing_zones_management_group_id && output.assignment_scopes.sandboxes == var.sandboxes_management_group_id
    error_message = "Assignments must target the three intended sibling management groups."
  }
  assert {
    condition     = output.assignment_enforcement.landing_zones == true && output.assignment_enforcement.sandboxes == false
    error_message = "Landing zones must be enforced while Sandboxes use the relaxed posture."
  }
}

run "platform_remediation_and_built_in_hydration" {
  command = plan
  assert {
    condition     = length(output.remediation_references["platform"]) > 0 && output.principal_ids["platform"] != null
    error_message = "Platform must select a remediable built-in member and expose identity/remediation outputs."
  }
  assert {
    condition     = length(output.definition_ids) == 2 && output.definition_ids["network_watcher_dine"] != null
    error_message = "Built-in definitions must hydrate into stable logical definition IDs."
  }
}

run "governed_exemption_uses_child_scope_and_assignment_key" {
  command = plan
  assert {
    condition     = output.exemption_scopes["lz_subscription_waiver"] == var.landing_zone_subscription_id && can(regex("policyExemptions", output.exemption_ids["lz_subscription_waiver"]))
    error_message = "The governed waiver must attach to the Landing zones assignment at the child subscription scope."
  }
}

run "logical_outputs_are_stable" {
  command = plan
  assert {
    condition     = length(setsubtract(keys(output.initiative_ids), ["platform_baseline", "landing_zones_guardrails", "sandboxes_baseline"])) == 0 && length(setsubtract(["platform_baseline", "landing_zones_guardrails", "sandboxes_baseline"], keys(output.initiative_ids))) == 0 && length(setsubtract(keys(output.assignment_ids), ["platform", "landing_zones", "sandboxes"])) == 0 && length(setsubtract(keys(output.exemption_ids), ["lz_subscription_waiver"])) == 0
    error_message = "CAF logical output keys must remain stable for downstream automation."
  }
}
