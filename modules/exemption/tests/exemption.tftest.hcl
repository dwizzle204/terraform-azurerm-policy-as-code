mock_provider "azurerm" {
  mock_resource "azurerm_management_group_policy_exemption" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/preview/providers/Microsoft.Authorization/policyExemptions/exemption_contract_test" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_exemption" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyExemptions/exemption_contract_test" }
    override_during = plan
  }
  mock_resource "azurerm_resource_group_policy_exemption" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1/providers/Microsoft.Authorization/policyExemptions/exemption_contract_test" }
    override_during = plan
  }
}

variables {
  name                 = "exemption_contract_test"
  display_name         = "Exemption Contract Test"
  description          = "Offline contract test exemption"
  scope                = "/subscriptions/00000000-0000-0000-0000-000000000000"
  policy_assignment_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_assignment"
}

run "subscription_scope_selects_subscription_exemption" {
  command = plan

  assert {
    condition     = output.exemption.id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyExemptions/exemption_contract_test"
    error_message = "Subscription scope must select the subscription exemption resource"
  }

  assert {
    condition     = output.exemption.category == "Waiver"
    error_message = "Default exemption category must be Waiver"
  }

  assert {
    condition     = output.exemption.expires_on == null
    error_message = "No expiry by default"
  }
}

run "expires_on_gets_time_component" {
  command = plan

  variables {
    expires_on = "2030-01-31"
  }

  assert {
    condition     = output.exemption.expires_on == "2030-01-31T23:00:00Z"
    error_message = "Date-only expiry must be normalized with a time component"
  }
}

run "camel_case_references_are_converted" {
  command = plan

  variables {
    policy_definition_reference_ids = ["deploy_asc_standard", "member_two"]
    camel_case_references           = true
  }

  assert {
    condition     = length(output.exemption.definition_reference_ids) == 2 && contains(output.exemption.definition_reference_ids, "DeployAscStandard") && contains(output.exemption.definition_reference_ids, "MemberTwo")
    error_message = "camel_case_references=true must convert snake/kebab references to CamelCase"
  }
}

run "metadata_is_json_encoded" {
  command = plan

  variables {
    metadata = { requestedBy = "platform-team" }
  }

  assert {
    condition     = output.exemption.metadata.requestedBy == "platform-team" && jsondecode(azurerm_subscription_policy_exemption.subscription_exemption[0].metadata).requestedBy == "platform-team"
    error_message = "Metadata must be passed through in the output and JSON encoded on the exemption resource"
  }
}

run "invalid_category_fails_variable_validation" {
  command = plan

  variables {
    exemption_category = "Invalid"
  }

  expect_failures = [
    var.exemption_category,
  ]
}

run "name_over_64_chars_fails_variable_validation" {
  command = plan

  variables {
    name = join("", [for i in range(65) : "x"])
  }

  expect_failures = [
    var.name,
  ]
}

run "malformed_metadata_fails_validation" {
  command = plan

  variables {
    metadata = [1, 2, 3]
  }

  expect_failures = [
    var.metadata,
  ]
}

run "governed_waiver_with_expiry_renders_governance" {
  command = plan

  variables {
    exemption_category = "Waiver"
    expires_on         = "2030-01-31"
    governed = {
      owner               = "platform-team"
      tracking_reference  = "RISK-2914"
      reason              = "Legacy dependency incompatible with control"
      governed_created_on = "2026-01-15"
    }
  }

  assert {
    condition     = output.governance.owner == "platform-team" && output.governance.trackingReference == "RISK-2914" && output.governance.created == "2026-01-15"
    error_message = "Governed metadata must carry stable governance fields and creation date (#10)"
  }

}

# waiver-without-expiry covered by scripts/test.sh negative check; mitigated-without-mitigation by TMP7 check
# covered by the scripts/test.sh negative checks — plan-time file() errors
# abort terraform test runs rather than failing assertions
