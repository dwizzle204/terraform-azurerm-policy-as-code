mock_provider "azurerm" {
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
