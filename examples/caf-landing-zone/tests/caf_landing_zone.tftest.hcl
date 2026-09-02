# Credential-free contract tests. These assertions consume outputs propagated by
# modules/intent and the underlying assignment/exemption modules, rather than
# reconstructing the example inputs in test-only outputs.
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
  governed_waiver_expires_on        = "2099-12-31"
}

run "caf_assignment_scopes_are_wired" {
  command = plan
  assert {
    condition = output.assignment_scopes == {
      platform = var.platform_management_group_id, landing_zones = var.landing_zones_management_group_id, sandboxes = var.sandboxes_management_group_id
    }
    error_message = "Intent assignment scopes must resolve to the three intended sibling management groups."
  }
  assert {
    condition     = alltrue([for id in values(output.assignment_ids) : id != null && id != ""])
    error_message = "Intent assignment IDs must be created for every CAF assignment."
  }
}

run "caf_enforcement_posture_is_wired" {
  command = plan
  assert {
    condition     = output.assignment_enforcement.landing_zones == true && output.assignment_enforcement.sandboxes == false
    error_message = "Landing zones must be enforced while Sandboxes use DoNotEnforce."
  }
  assert {
    condition     = output.initiative_ids["landing_zones_guardrails"] != null && output.initiative_ids["sandboxes_baseline"] != null
    error_message = "Sibling-scoped initiatives must be created and exposed by intent."
  }
}

run "platform_remediation_and_identity_are_wired" {
  command = plan
  # intent exposes selected member references, not full remediation task objects;
  # set_assignment.remediation_tasks is the lower-level task-ID output.
  assert {
    condition     = length(output.remediation_references["platform"]) > 0
    error_message = "Platform intent must select a remediable member reference."
  }
  assert {
    condition     = output.assignment_principal_ids["platform"] != null && output.assignment_principal_ids["platform"] != ""
    error_message = "Platform remediation must have a managed identity principal."
  }
}

run "definitions_and_governed_exemption_are_wired" {
  command = plan
  assert {
    condition     = length(setsubtract(keys(output.definition_ids), ["network_watcher_dine", "allowed_locations"])) == 0 && length(setsubtract(["network_watcher_dine", "allowed_locations"], keys(output.definition_ids))) == 0
    error_message = "Intent must hydrate both declared built-in definitions."
  }
  assert {
    condition     = output.exemption_scopes["lz_subscription_waiver"] == var.landing_zone_subscription_id && output.exemption_ids["lz_subscription_waiver"] != null && output.assignment_ids["landing_zones"] != null
    error_message = "The governed waiver must attach to the Landing zones assignment at the child subscription scope."
  }
}
