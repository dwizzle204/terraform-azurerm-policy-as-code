mock_provider "azurerm" {}

variables {
  policy_category = "Testing"
  policy_name     = "naming_contract_policy"
  file_path       = "tests/fixtures/test_policy.json"
}

run "baseline_name" {
  command = plan
}

run "stable_name_across_identical_inputs" {
  command = plan

  # identical inputs -> byte-identical physical name across independent runs
  assert {
    condition     = output.azure_definition_name == run.baseline_name.azure_definition_name
    error_message = "Identical inputs must produce the same physical definition name"
  }

  assert {
    condition     = length(output.definition_name_suffix) == 8 && can(regex("^[0-9a-f]+$", output.definition_name_suffix))
    error_message = "Suffix must be 8 lowercase hex characters derived from documented inputs"
  }
}

run "schema_change_changes_name" {
  command = plan

  variables {
    policy_parameters = jsonencode({ allowedLocations = { type = "Array", metadata = { displayName = "Allowed locations changed" } } })
  }

  assert {
    condition     = output.azure_definition_name != run.baseline_name.azure_definition_name
    error_message = "A parameter-schema change must produce a different deterministic definition name"
  }
}

run "name_length_within_azure_limits" {
  command = plan

  variables {
    policy_name = "this_is_a_long_policy_name_used_to_verify_prefix_truncation_1234" # 64 chars (module validation max)
  }

  assert {
    condition     = length(output.azure_definition_name) <= 64
    error_message = "Definition names must satisfy the Azure 64 character limit even for very long logical names"
  }
}
