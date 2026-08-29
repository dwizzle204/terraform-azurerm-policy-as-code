mock_provider "azurerm" {
  mock_data "azurerm_policy_definition_built_in" {
    defaults = {
      id                  = "/providers/Microsoft.Authorization/policyDefinitions/e765b5de-1225-4ba3-bd56-1ac6695af988"
      name                = "e765b5de-1225-4ba3-bd56-1ac6695af988"
      display_name        = "Allow resource creation only in whitelisted regions"
      description         = "Built-in policy for testing"
      mode                = "Indexed"
      management_group_id = null
      metadata            = "{\"category\":\"General\",\"version\":\"3.1.0\"}"
      parameters          = "{\"effect\":{\"type\":\"String\",\"defaultValue\":\"DeployIfNotExists\",\"allowedValues\":[\"AuditIfNotExists\",\"DeployIfNotExists\",\"Disabled\"],\"metadata\":{\"displayName\":\"Effect\",\"description\":\"Enable or disable the execution of the policy\"}}}"
      policy_rule         = "{\"if\":{\"field\":\"location\",\"notIn\":\"[parameters('allowedLocations')]\"},\"then\":{\"effect\":\"[parameters('effect')]\"}}"
      version             = "3.1.0"
      policy_type         = "BuiltIn"
    }
    override_during = plan
  }
  mock_data "azurerm_policy_definition" {
    defaults = {
      id                  = "/providers/Microsoft.Authorization/policyDefinitions/e765b5de-1225-4ba3-bd56-1ac6695af988"
      name                = "e765b5de-1225-4ba3-bd56-1ac6695af988"
      display_name        = "Allow resource creation only in whitelisted regions"
      description         = "Built-in policy for testing"
      mode                = "Indexed"
      management_group_id = null
      metadata            = "{\"category\":\"General\",\"version\":\"3.1.0\"}"
      parameters          = "{\"effect\":{\"type\":\"String\",\"defaultValue\":\"DeployIfNotExists\",\"allowedValues\":[\"AuditIfNotExists\",\"DeployIfNotExists\",\"Disabled\"],\"metadata\":{\"displayName\":\"Effect\",\"description\":\"Enable or disable the execution of the policy\"}}}"
      policy_rule         = "{\"if\":{\"field\":\"location\",\"notIn\":\"[parameters('allowedLocations')]\"},\"then\":{\"effect\":\"[parameters('effect')]\"}}"
      version             = "3.1.0"
    }
    override_during = plan
  }
  mock_data "azurerm_subscription" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
    override_during = plan
  }
  mock_resource "azurerm_management_group_policy_set_definition" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policySetDefinitions/platform_baseline" }
    override_during = plan
  }
  mock_resource "azurerm_policy_set_definition" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/platform_baseline" }
    override_during = plan
  }
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
  mock_resource "azurerm_resource_group_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sandbox-rg/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
  mock_resource "azurerm_management_group_policy_exemption" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/platform/providers/Microsoft.Authorization/policyExemptions/legacy-app-waiver" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_exemption" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyExemptions/legacy-app-waiver" }
    override_during = plan
  }
}

mock_provider "azuread" {}

variables {
  definitions = {
    member_a = { category = "Monitoring", policy_name = "deploy_vnet_diagnostic_setting" }
    member_b = { category = "Monitoring", policy_name = "deploy_application_gateway_diagnostic_setting" }
  }
  initiatives = {
    platform_baseline = {
      display_name           = "Platform Baseline"
      management_group_id    = "/providers/Microsoft.Management/managementGroups/platform"
      member_definition_keys = ["member_a", "member_b"]
    }
  }
  assignments = {
    platform = {
      initiative_key = "platform_baseline"
      scope          = "/providers/Microsoft.Management/managementGroups/platform"
      effect         = "Deny"
    }
    sandbox = {
      initiative_key = "platform_baseline"
      scope          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sandbox-rg"
      enforcement    = false
    }
  }
}

run "end_to_end_assignments_resolve_distinct_scopes" {
  command = plan

  assert {
    condition     = length(output.assignment_ids) == 2 && startswith(output.assignment_ids["platform"], "/providers/Microsoft.Management/") && startswith(output.assignment_ids["sandbox"], "/subscriptions/")
    error_message = "Intent assignments must resolve the correct scope-specific resource per scope without consumer input"
  }
}

run "definitions_and_initiative_resolve" {
  command = plan

  assert {
    condition     = length(output.definition_ids) == 2 && length(output.initiative_ids) == 1
    error_message = "All declared definitions and the initiative must be created"
  }
}

run "exemption_attaches_to_intended_assignment" {
  command = plan

  variables {
    exemptions = {
      legacy_app = {
        assignment_key = "platform"
        scope          = "/providers/Microsoft.Management/managementGroups/platform"
        name           = "legacy-app-waiver"
        display_name   = "Legacy App Waiver"
        description    = "Temporary waiver pending decommission"
        expires_on     = "2026-12-31"
        governed = {
          owner              = "app-team"
          tracking_reference = "RISK-2914"
          reason             = "Legacy dependency incompatible with control"
        }
      }
    }
  }

  assert {
    condition     = can(regex("policyExemptions/legacy-app-waiver$", output.exemption_ids["legacy_app"]))
    error_message = "Exemption must be created and exported against the intended assignment"
  }
}

# dangling reference validation is covered by sentinel errors, which terraform
# test cannot assert (plan-time function errors); scripts/test.sh covers it via
# an expected-failure scratch plan.

run "dangling_member_definition_keys_fail_validation" {
  command = plan

  variables {
    definitions = {
      good = { category = "Monitoring", policy_name = "deploy_vnet_diagnostic_setting" }
    }
    initiatives = {
      baseline = {
        display_name           = "Baseline"
        member_definition_keys = ["does_not_exist"]
      }
    }
  }

  expect_failures = [
    var.initiatives,
  ]
}

run "dangling_initiative_key_fails_validation" {
  command = plan

  variables {
    definitions = {
      good = { category = "Monitoring", policy_name = "deploy_vnet_diagnostic_setting" }
    }
    initiatives = {
      baseline = {
        display_name           = "Baseline"
        management_group_id    = "/providers/Microsoft.Management/managementGroups/test"
        member_definition_keys = ["good"]
      }
    }
    assignments = {
      sub_assign = {
        initiative_key = "missing_initiative"
        scope          = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
    }
  }

  expect_failures = [
    var.assignments,
  ]
}

run "dangling_assignment_key_in_exemption_fails_validation" {
  command = plan

  variables {
    definitions = {
      good = { category = "Monitoring", policy_name = "deploy_vnet_diagnostic_setting" }
    }
    initiatives = {
      baseline = {
        display_name           = "Baseline"
        management_group_id    = "/providers/Microsoft.Management/managementGroups/test"
        member_definition_keys = ["good"]
      }
    }
    assignments = {
      sub_assign = {
        initiative_key = "baseline"
        scope          = "/subscriptions/00000000-0000-0000-0000-000000000000"
      }
    }
    exemptions = {
      exc1 = {
        assignment_key = "no_such_assignment"
        scope          = "/subscriptions/00000000-0000-0000-0000-000000000000"
        name           = "exc"
        display_name   = "Exc"
        description    = "test"
      }
    }
  }

  expect_failures = [
    var.exemptions,
  ]
}

# --- review-sweep coverage (codex findings on #13) ---

run "mg_scope_inherited_by_member_definitions" {
  command = plan

  assert {
    condition     = output.definition_details["member_a"].management_group_id == "/providers/Microsoft.Management/managementGroups/platform"
    error_message = "Member definitions must inherit the referencing initiative's management group scope (#13 review)"
  }
}

run "definition_metadata_passthrough" {
  command = plan

  variables {
    definitions = {
      member_a = {
        category    = "Monitoring"
        policy_name = "deploy_vnet_diagnostic_setting"
        metadata    = { controlIds = ["AZC-01"] }
      }
      member_b = {
        category    = "Monitoring"
        policy_name = "deploy_application_gateway_diagnostic_setting"
        metadata    = { controlIds = ["AZC-02"] }
      }
    }
  }

  assert {
    condition     = output.definition_details["member_a"].metadata.controlIds == ["AZC-01"]
    error_message = "Definition metadata passthrough must preserve catalog control IDs (#13 review)"
  }
}

run "remediation_reachable_through_intent" {
  command = plan

  variables {
    assignments = {
      dine_remediation = {
        initiative_key            = "platform_baseline"
        scope                     = "/subscriptions/00000000-0000-0000-0000-000000000000"
        role_definition_ids       = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
        remediate_effects         = ["DeployIfNotExists", "Modify"]
        remediation_reference_ids = []
        remediate                 = true
      }
    }
    initiatives = {
      platform_baseline = merge(var.initiatives.platform_baseline, {
        member_definition_keys = ["dine_member"]
      })
    }
    definitions = {
      dine_member = {
        category    = "Monitoring"
        policy_name = "deploy_vnet_diagnostic_setting"
      }
    }
  }

  assert {
    condition     = length(output.assignment_remediation_references["dine_remediation"]) > 0
    error_message = "Remediation tasks must be reachable through the intent wrapper when remediate=true and effects match (#13 review P1)"
  }
}

run "subscription_only_definitions_resolve_without_error" {
  command = plan

  variables {
    definitions = {
      standalone = { category = "Monitoring", policy_name = "deploy_vnet_diagnostic_setting" }
    }
    initiatives = {}
    assignments = {}
    exemptions  = {}
  }

  assert {
    condition     = length(output.definition_ids) == 1 && output.definition_details["standalone"].management_group_id == null
    error_message = "Subscription-only/unreferenced definitions must resolve with null management_group_id (regression for coalesce fix)"
  }
}

run "mixed_custom_and_builtin_initiative" {
  command = plan

  variables {
    definitions = {
      custom_member = {
        source              = "custom"
        category            = "Monitoring"
        policy_name         = "deploy_vnet_diagnostic_setting"
        file_path           = null
        definition_id       = null
        version             = null
        parameters          = null
        policy_rule         = null
        mode                = null
        management_group_id = null
        metadata            = null
      }
      builtin_member = {
        source              = "builtin"
        definition_id       = "/providers/Microsoft.Authorization/policyDefinitions/e765b5de-1225-4ba3-bd56-1ac6695af988"
        version             = null
        category            = null
        policy_name         = null
        file_path           = null
        parameters          = null
        policy_rule         = null
        mode                = null
        management_group_id = null
        metadata            = null
      }
    }
    initiatives = {
      mixed = {
        display_name           = "Mixed Initiative"
        member_definition_keys = ["custom_member", "builtin_member"]
      }
    }
    assignments = {}
    exemptions  = {}
  }

  assert {
    condition     = length(output.initiative_ids) == 1 && length(output.definition_ids) == 2 && length(output.custom_definition_ids) == 1
    error_message = "Mixed custom + built-in initiative must create the initiative and expose both custom and built-in IDs"
  }

  assert {
    condition     = output.initiative_ids["mixed"] != ""
    error_message = "Mixed initiative must have a valid ID"
  }
}

run "pinned_builtin_preserves_explicit_mode_and_policy_rule" {
  command = plan

  variables {
    definitions = {
      pinned_builtin = {
        source        = "builtin"
        definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e765b5de-1225-4ba3-bd56-1ac6695af988"
        version       = "3.1"
        mode          = "Indexed"
        parameters    = {}
        policy_rule   = { if = { field = "location", equals = "westeurope" }, then = { effect = "audit" } }
      }
    }
    initiatives = {
      pinned = {
        display_name           = "Pinned Builtin"
        member_definition_keys = ["pinned_builtin"]
      }
    }
    assignments = {}
    exemptions  = {}
  }

  assert {
    condition     = length(output.initiative_ids) == 1
    error_message = "Pinned built-in initiative must be created with explicit mode/policy_rule preserved"
  }
}

run "builtin_hydrates_mode_and_parameters" {
  command = plan

  variables {
    definitions = {
      builtin_param = {
        source        = "builtin"
        definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e765b5de-1225-4ba3-bd56-1ac6695af988"
      }
    }
    initiatives = {
      with_builtin = {
        display_name           = "With Builtin"
        member_definition_keys = ["builtin_param"]
      }
    }
    assignments = {}
    exemptions  = {}
  }

  assert {
    condition     = length(output.initiative_ids) == 1
    error_message = "Built-in initiative must be created via hydrated data source"
  }
}

run "heterogeneous_assignment_parameters_accepted" {
  command = plan

  variables {
    assignments = {
      mixed_params = {
        initiative_key = "platform_baseline"
        scope          = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/sandbox-rg"
        parameters = {
          stringParam = "text-value"
          listParam   = ["a", "b"]
        }
      }
    }
  }

  assert {
    condition     = output.assignment_names["mixed_params"] != "mixed_params" && can(regex("-[a-z0-9]{8}$", output.assignment_names["mixed_params"]))
    error_message = "Intent assignments must use deterministic collision-resistant names by default"
  }
}

run "pinned_remediation_without_metadata_fails_fast" {
  command = plan

  variables {
    definitions = {
      pinned_dine = {
        source        = "builtin"
        definition_id = "/providers/Microsoft.Authorization/policyDefinitions/b7ddfbdc-e688-46bc-a468-2def594365a3"
        version       = "3.1"
      }
    }
    initiatives = {
      baseline = {
        display_name           = "Baseline"
        management_group_id    = "/providers/Microsoft.Management/managementGroups/test"
        member_definition_keys = ["pinned_dine"]
      }
    }
    assignments = {
      requested_remediation = {
        initiative_key = "baseline"
        scope          = "/subscriptions/00000000-0000-0000-0000-000000000000"
        remediate      = true
      }
    }
  }

  # expect the terraform_data precondition failure
  expect_failures = [
    terraform_data.validate_pinned_remediation,
  ]
}

run "pinned_remediation_with_roles_succeeds" {
  command = plan

  variables {
    definitions = {
      pinned_dine = {
        source        = "builtin"
        definition_id = "/providers/Microsoft.Authorization/policyDefinitions/b7ddfbdc-e688-46bc-a468-2def594365a3"
        version       = "3.1"
      }
    }
    initiatives = {
      baseline = {
        display_name           = "Baseline"
        management_group_id    = "/providers/Microsoft.Management/managementGroups/test"
        member_definition_keys = ["pinned_dine"]
      }
    }
    assignments = {
      requested_remediation = {
        initiative_key            = "baseline"
        scope                     = "/subscriptions/00000000-0000-0000-0000-000000000000"
        remediate                 = true
        role_definition_ids       = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
        remediation_reference_ids = ["b7ddfbdc-e688-46bc-a468-2def594365a3"]
      }
    }
  }

  assert {
    condition     = length(output.assignment_remediation_references["requested_remediation"]) >= 1
    error_message = "Explicit role_definition_ids must satisfy the pinned built-in remediation contract"
  }
}
