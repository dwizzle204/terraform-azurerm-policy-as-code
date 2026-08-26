mock_provider "azurerm" {}

# NOTE: the missing-file negative case cannot be asserted with terraform test
# (plan-time function errors abort the run rather than fail assertions).
# scripts/test.sh covers it with an expected-failure scratch plan.

run "loads_definition_from_file_path" {
  command = plan

  variables {
    file_path       = "tests/fixtures/test_policy.json"
    policy_name     = "test_policy"
    policy_category = null
  }

  assert {
    condition     = output.name == "test_policy"
    error_message = "Definition name should come from var.policy_name"
  }

  assert {
    condition     = output.metadata.category == "Testing" && output.metadata.version == "1.2.3"
    error_message = "Category and version should be read from fixture metadata"
  }

  assert {
    condition     = output.definition.mode == "Indexed"
    error_message = "Mode should be read from the fixture properties.mode"
  }

  assert {
    condition     = jsondecode(jsonencode(output.rules)).then.effect == "Deny"
    error_message = "Policy rule should be loaded from the fixture"
  }
}

# NOTE: documents current upstream behavior — file metadata.version takes
# precedence over var.policy_version because the metadata local prefers
# policy_object.properties.metadata via coalesce. Only policy_mode is honored.
run "runtime_overrides_take_precedence_over_file" {
  command = plan

  variables {
    file_path       = "tests/fixtures/test_policy.json"
    policy_name     = "test_policy"
    policy_category = null
    policy_version  = "9.9.9"
    policy_mode     = "All"
  }

  assert {
    condition     = output.definition.mode == "All"
    error_message = "Explicit var.policy_mode must override library attributes"
  }

  assert {
    condition     = output.metadata.version == "1.2.3"
    error_message = "File metadata.version currently wins over var.policy_version (documented upstream behavior)"
  }
}

run "library_path_resolution_from_repo_root" {
  command = plan

  variables {
    policy_category = "Monitoring"
    policy_name     = "deploy_vnet_diagnostic_setting"
  }

  assert {
    condition     = output.name == "deploy_vnet_diagnostic_setting"
    error_message = "Library resolution via policies/<Category>/<name>.json must load the named definition"
  }
}

run "runtime_only_definition_without_file" {
  command = plan

  variables {
    policy_category   = "Custom Category"
    policy_name       = "custom_runtime_definition"
    display_name      = "Custom Runtime Definition"
    policy_rule       = jsonencode({ if = { field = "location", equals = "westeurope" }, then = { effect = "audit" } })
    policy_parameters = jsonencode({})
    policy_metadata   = jsonencode({ category = "Custom Category" })
  }

  assert {
    condition     = output.rules.then.effect == "audit"
    error_message = "Fully runtime-defined policies remain supported; string-form inputs are normalized to objects (#4)"
  }

  assert {
    condition     = output.metadata.category == "Custom Category"
    error_message = "Runtime metadata should be used when no file resolves"
  }
}

run "malformed_policy_rule_fails_validation" {
  command = plan

  variables {
    file_path   = "tests/fixtures/test_policy.json"
    policy_name = "test_policy"
    policy_rule = ["not", "an", "object"]
  }

  expect_failures = [
    var.policy_rule,
  ]
}
