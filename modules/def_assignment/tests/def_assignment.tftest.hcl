mock_provider "azurerm" {
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/preview/providers/Microsoft.Authorization/policyAssignments/mock_definition" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_definition", identity = { principal_id = "22222222-2222-2222-2222-222222222222", tenant_id = "33333333-3333-3333-3333-333333333333", type = "SystemAssigned" } }
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

# issue #1/#3: remediation requires explicit effect configuration (opt-in)
run "remediation_requires_explicit_effect_configuration" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    definition          = merge(var.definition, { policy_rule = jsonencode({ if = {}, then = { effect = "DeployIfNotExists" } }) })
  }

  assert {
    condition     = output.remediation_id != ""
    error_message = "DINE-capable identity assignment should create a remediation task"
  }
}

# issue #62: enforcementMode = DoNotEnforce must not suppress an explicitly
# requested remediation task (Azure supports manual DINE remediation under
# DoNotEnforce). Request-time enforcement and remediation are decoupled.
run "remediation_created_under_do_not_enforce" {
  command = plan

  variables {
    assignment_enforcement_mode = false
    remediate_effects           = ["DeployIfNotExists", "Modify"]
    role_definition_ids         = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    definition                  = merge(var.definition, { policy_rule = jsonencode({ if = {}, then = { effect = "DeployIfNotExists" } }) })
  }

  assert {
    condition     = output.remediation_id != ""
    error_message = "enforcement=false with DINE + identity + remediation opt-in must still create a remediation task (#62)"
  }

  assert {
    condition     = output.enforcement_mode == false
    error_message = "The assignment itself must keep DoNotEnforce while remediation is created"
  }
}

# issue #62: Audit assignments must never receive remediation, even with
# enforcement disabled, identity, and explicit opt-in.
run "audit_under_do_not_enforce_still_no_remediation" {
  command = plan

  variables {
    assignment_enforcement_mode = false
    remediate_effects           = ["DeployIfNotExists", "Modify"]
    role_definition_ids         = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    definition                  = merge(var.definition, { policy_rule = jsonencode({ if = {}, then = { effect = "Audit" } }) })
  }

  assert {
    condition     = output.remediation_id == ""
    error_message = "Audit must never produce a remediation task regardless of enforcement mode (#62)"
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

# ---- #2: collision-resistant naming (opt-in) ----

run "collision_resistant_names_differ_for_shared_prefixes" {
  command = plan

  variables {
    collision_resistant_naming = true
    assignment_scope           = "/providers/Microsoft.Management/managementGroups/preview"
    definition                 = merge(var.definition, { name = "platform_baseline_security_initiative_rollout_a" })
  }

  assert {
    condition     = startswith(output.assignment_name, format("%s-", substr(lower(var.definition.name), 0, 15)))
    error_message = "Name should be the truncated lowercase prefix followed by '-' and the deterministic hash"
  }

  assert {
    condition     = length(output.assignment_name) == 24 && can(regex("^[a-z0-9_-]{15}-[0-9a-f]{8}$", output.assignment_name))
    error_message = "MG scope: prefix + '-' + 8-char hash must total exactly 24 characters"
  }
}

run "collision_resistant_names_differ_between_logical_identities" {
  command = plan

  variables {
    collision_resistant_naming = true
    assignment_scope           = "/providers/Microsoft.Management/managementGroups/preview"
    definition                 = merge(var.definition, { name = "platform_baseline_security_initiative_rollout_b" })
  }

  assert {
    condition     = output.assignment_name != run.collision_resistant_names_differ_for_shared_prefixes.assignment_name
    error_message = "Two logical identities sharing a >24 character prefix must not collide"
  }
}

run "collision_resistant_names_stable_and_limited" {
  command = plan

  variables {
    collision_resistant_naming = true
    assignment_name            = "subscription_scope_collision_resistant_naming_contract_check_long_name"
  }

  assert {
    condition     = length(output.assignment_name) <= 64 && can(regex("-[0-9a-f]{8}$", output.assignment_name))
    error_message = "Subscription-scope names stay within limits and end in the deterministic hash"
  }
}

run "legacy_truncation_unchanged_by_default" {
  command = plan

  variables {
    assignment_name = "legacy_truncation_mode_is_default_and_must_remain_stable"
  }

  assert {
    condition     = output.assignment_name == lower(substr(var.assignment_name, 0, 64))
    error_message = "Default mode must preserve today's truncation behavior byte-for-byte"
  }
}

run "default_remediation_is_opt_in" {
  command = plan

  variables {
    role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
  }

  assert {
    condition     = output.remediation_id == ""
    error_message = "Default (no remediate_effects) must create no remediation task - opt-in (#3)"
  }
}

run "assignment_effect_override_drives_eligibility" {
  command = plan

  variables {
    assignment_effect   = "Modify"
    remediate_effects   = ["Modify"]
    role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
  }

  assert {
    condition     = output.remediation_id != ""
    error_message = "An assignment_effect override matching the filter makes the definition eligible"
  }
}

# lowercase literal then.effect from the real library must classify as DINE
run "lowercase_literal_then_effect_is_remediable" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    # definition contract carries policy_rule/parameters as JSON strings
    definition = merge(var.definition, {
      policy_rule = file("tests/fixtures/preview_deploy_linux_azure_monitor_vm_agent.json") == null ? "" : jsonencode(jsondecode(file("tests/fixtures/preview_deploy_linux_azure_monitor_vm_agent.json")).properties.policyRule)
      parameters  = jsonencode(jsondecode(file("tests/fixtures/preview_deploy_linux_azure_monitor_vm_agent.json")).properties.parameters)
    })
  }

  assert {
    condition     = output.remediation_id != ""
    error_message = "A lowercase deployIfNotExists literal in then.effect must be classified as remediable"
  }
}


run "def_assignment_resource_selector_and_override_passthrough" {
  command = plan

  variables {
    resource_selectors = [
      { name = "sdp", selectors = [{ kind = "resourceWithoutLocation", not_in = ["microsoft.contoso/legacy"] }] }
    ]
    overrides = [
      { value = "DeployIfNotExists", selectors = [{ kind = "resourceLocation", in = ["westeurope"] }] }
    ]
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.def[0].resource_selectors[0].selectors[0].kind == "resourceWithoutLocation"
    error_message = "Resource selector kinds must pass through on def_assignment"
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.def[0].overrides[0].selectors[0].kind == "resourceLocation"
    error_message = "Override selectors must be supported on def_assignment (new capability, #8)"
  }

  assert {
    condition     = length(azurerm_subscription_policy_assignment.def[0].resource_selectors[0].selectors[0].not_in) == 1 && contains(azurerm_subscription_policy_assignment.def[0].resource_selectors[0].selectors[0].not_in, "microsoft.contoso/legacy")
    error_message = "Resource selector not_in values must pass through (#8)"
  }

  assert {
    condition     = length(azurerm_subscription_policy_assignment.def[0].overrides[0].selectors[0].in) == 1 && contains(azurerm_subscription_policy_assignment.def[0].overrides[0].selectors[0].in, "westeurope")
    error_message = "Override selector in values must pass through (#8)"
  }
}

run "def_assignment_invalid_override_kind_fails_validation" {
  command = plan

  variables {
    overrides = [
      { value = "Audit", selectors = [{ kind = "nope" }] }
    ]
  }

  expect_failures = [
    var.overrides,
  ]
}

run "group_membership_permission_path_creates_remediation" {
  command = plan

  variables {
    aad_group_remediation_object_ids = ["11111111-1111-1111-1111-111111111111"]
    remediate_effects                = ["DeployIfNotExists"]
    definition = merge(var.definition, {
      policy_rule = jsonencode({ if = {}, then = { effect = "DeployIfNotExists", details = { roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"] } } })
    })
  }

  assert {
    condition     = length(resource.azuread_group_member.remediation) == 1
    error_message = "Group-based permission provisioning must create the group membership prerequisite"
  }

  assert {
    condition     = output.remediation_id != ""
    error_message = "Group-based permission provisioning must retain remediation creation"
  }

}

run "role_assignment_permission_path_creates_remediation" {
  command = plan

  variables {
    aad_group_remediation_object_ids = []
    role_definition_ids              = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    remediate_effects                = ["DeployIfNotExists"]
    definition = merge(var.definition, {
      policy_rule = jsonencode({ if = {}, then = { effect = "DeployIfNotExists" } })
    })
  }

  assert {
    condition     = length(resource.azurerm_role_assignment.remediation) == 1
    error_message = "Role-assignment permission provisioning must create the RBAC prerequisite"
  }

  assert {
    condition     = output.remediation_id != ""
    error_message = "Role-assignment permission provisioning must retain remediation creation"
  }

}
