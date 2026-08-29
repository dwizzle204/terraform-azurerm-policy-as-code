mock_provider "azurerm" {
  # explicit override for the module's Azure data source (issue #16)
  mock_data "azurerm_subscription" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000" }
    override_during = plan
  }
  mock_resource "azurerm_management_group_policy_set_definition" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/test/providers/Microsoft.Authorization/policySetDefinitions/initiative_contract_test" }
    override_during = plan
  }
  mock_resource "azurerm_policy_set_definition" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/initiative_contract_test" }
    override_during = plan
  }
}

variables {
  initiative_name         = "initiative_contract_test"
  initiative_display_name = "Initiative Contract Test"
  management_group_id     = "/providers/Microsoft.Management/managementGroups/test"
  member_definitions = [
    {
      id           = "/providers/Microsoft.Authorization/policyDefinitions/member_a"
      name         = "member_a"
      display_name = "Member A"
      mode         = "All"
      metadata     = jsonencode({ category = "Monitoring", version = "1.0.0" })
      parameters = jsonencode({
        effect        = { type = "String", defaultValue = "AuditIfNotExists", allowedValues = ["AuditIfNotExists", "Disabled"] }
        retentionDays = { type = "String", defaultValue = "30" }
      })
      policy_rule = jsonencode({ if = {}, then = { effect = "" } })
    },
    {
      id           = "/providers/Microsoft.Authorization/policyDefinitions/member_b"
      name         = "member_b"
      display_name = "member-b"
      mode         = "All"
      metadata     = jsonencode({ category = "Monitoring" })
      parameters   = jsonencode({})
      policy_rule  = jsonencode({ if = {}, then = { details = { roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"] } } })
    }
  ]
}

run "merged_parameters_are_combined_across_members" {
  command = plan

  assert {
    condition     = length(keys(output.parameters)) == 2
    error_message = "Merged parameter set should contain exactly effect and retentionDays"
  }

  assert {
    condition     = output.parameters["effect"].defaultValue == "AuditIfNotExists"
    error_message = "Effect parameter should carry the source definition default"
  }
}

run "references_default_to_policy_names" {
  command = plan

  assert {
    condition     = [for ref in output.initiative.policy_definition_reference : ref.reference_id] == ["member_a", "member_b"]
    error_message = "Reference ids should default to policy names in order"
  }
}

run "camel_case_references_are_transformed" {
  command = plan

  variables {
    camel_case_references = true
  }

  assert {
    condition     = [for ref in output.initiative.policy_definition_reference : ref.reference_id] == ["MemberA", "MemberB"]
    error_message = "Camel case references should strip separators"
  }
}

run "role_definition_ids_collected_from_member_rules" {
  command = plan

  assert {
    condition     = length(output.role_definition_ids) == 1 && contains(output.role_definition_ids, "/providers/microsoft.authorization/roledefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c")
    error_message = "Role definitions from member policyRule.then.details should be collected and lowercased"
  }
}

run "non_compliance_messages_include_members_with_all_modes" {
  command = plan

  assert {
    condition     = lookup(output.non_compliance_messages, "member_a", "") != ""
    error_message = "member_a (mode All) should receive a non-compliance message entry"
  }

  assert {
    condition     = lookup(output.non_compliance_messages, "null", "") == "Flagged by Initiative: initiative_contract_test"
    error_message = "Default initiative-level non-compliance message should exist under the null key"
  }
}

run "duplicate_members_are_indexed" {
  command = plan

  variables {
    duplicate_members = true
    member_definitions = [
      { id = "/providers/Microsoft.Authorization/policyDefinitions/dup", name = "dup", display_name = "Dup", mode = "All", metadata = jsonencode({ category = "Monitoring" }), parameters = jsonencode({}), policy_rule = jsonencode({}) },
      { id = "/providers/Microsoft.Authorization/policyDefinitions/dup", name = "dup", display_name = "Dup", mode = "All", metadata = jsonencode({ category = "Monitoring" }), parameters = jsonencode({}), policy_rule = jsonencode({}) }
    ]
  }

  assert {
    condition     = [for ref in output.initiative.policy_definition_reference : ref.reference_id] == ["0_dup", "1_dup"]
    error_message = "Duplicate members should be prefixed with their index"
  }
}

run "identical_duplicate_parameter_schemas_merge" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/providers/Microsoft.Authorization/policyDefinitions/twin_a"
        name         = "twin_a"
        display_name = "Twin A"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters = jsonencode({
          sharedParam = { type = "String", defaultValue = "same", metadata = { displayName = "Shared" } }
          uniqueA     = { type = "String", defaultValue = "a" }
        })
        policy_rule = jsonencode({ if = {}, then = {} })
      },
      {
        id           = "/providers/Microsoft.Authorization/policyDefinitions/twin_b"
        name         = "twin_b"
        display_name = "Twin B"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters = jsonencode({
          sharedParam = { type = "String", defaultValue = "same", metadata = { displayName = "Shared" } }
          uniqueB     = { type = "String", defaultValue = "b" }
        })
        policy_rule = jsonencode({ if = {}, then = {} })
      }
    ]
  }

  assert {
    condition     = output.parameter_conflicts == {}
    error_message = "Byte-identical duplicate schemas must not be flagged as conflicts"
  }

  assert {
    condition     = contains(keys(output.parameters), "sharedParam") && !contains(keys(output.parameters), "uniqueA_sharedParam")
    error_message = "Identical duplicate schemas should merge into a single shared parameter entry"
  }
}

run "conflicting_schemas_reported_and_escape_hatch_works" {
  # escape hatch documented in #7: merge_parameters=false disables merging and
  # the hard failure, while detection stays visible via parameter_conflicts
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/providers/Microsoft.Authorization/policyDefinitions/conflict_a"
        name         = "conflict_a"
        display_name = "Conflict A"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters = jsonencode({
          sharedParam = { type = "String", defaultValue = "alpha", metadata = { displayName = "Shared" } }
        })
        policy_rule = jsonencode({ if = {}, then = {} })
      },
      {
        id           = "/providers/Microsoft.Authorization/policyDefinitions/conflict_b"
        name         = "conflict_b"
        display_name = "Conflict B"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters = jsonencode({
          sharedParam = { type = "String", defaultValue = "beta", metadata = { displayName = "Shared" } }
        })
        policy_rule = jsonencode({ if = {}, then = {} })
      }
    ]
    merge_parameters = false
  }

  assert {
    condition     = length(output.parameter_conflicts) == 1 && contains(keys(output.parameter_conflicts), "sharedParam")
    error_message = "Conflicting duplicate schemas must be reported with the parameter name as key"
  }

  assert {
    condition     = contains(output.parameter_conflicts["sharedParam"], "conflict_a") && contains(output.parameter_conflicts["sharedParam"], "conflict_b")
    error_message = "The conflict diagnostic must identify every declaring member definition"
  }
}

run "subscription_scoped_initiative_uses_subscription_resource" {
  command = plan

  variables {
    management_group_id = null
  }

  assert {
    condition     = can(regex("^/subscriptions/[^/]+/providers/Microsoft.Authorization/policySetDefinitions/", output.id))
    error_message = "Subscription-scoped initiatives must use azurerm_policy_set_definition"
  }

  assert {
    condition     = output.initiative.management_group_id == null
    error_message = "Subscription initiative output must have null management_group_id"
  }
}

run "management_group_scoped_initiative_uses_mg_resource" {
  command = plan

  assert {
    condition     = can(regex("^/providers/Microsoft.Management/managementGroups/", output.id))
    error_message = "Management-group initiatives must use azurerm_management_group_policy_set_definition"
  }
}

run "effect_conflicts_are_ignored_when_merge_effects_disabled" {
  command = plan

  variables {
    merge_effects = false
    member_definitions = [
      merge(var.member_definitions[0], {
        name       = "effect_a"
        parameters = jsonencode({ effect = { type = "String", defaultValue = "Audit" } })
      }),
      merge(var.member_definitions[1], {
        name       = "effect_b"
        parameters = jsonencode({ effect = { type = "String", defaultValue = "Deny" } })
      })
    ]
  }

  assert {
    condition     = output.parameter_conflicts == {}
    error_message = "Effect schemas may differ when merge_effects is false"
  }

  assert {
    condition     = contains(keys(output.parameters), "effect_effect_a") && contains(keys(output.parameters), "effect_effect_b")
    error_message = "Separate effect parameters must be emitted when effect merging is disabled"
  }
}





run "metadata_derived_three_part_version_canonicalized_on_resource" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/member_v3"
        name         = "member_v3"
        display_name = "Member V3"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring", version = "1.0.0" })
        parameters   = jsonencode({})
        policy_rule  = jsonencode({ if = {}, then = {} })
      }
    ]
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].version == "1.0.*"
    error_message = "Three-part metadata version 1.0.0 must be canonicalized to 1.0.* on the resource (AzureRM grammar)"
  }
}

run "metadata_derived_wildcard_version_unchanged_on_resource" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/member_w"
        name         = "member_w"
        display_name = "Member W"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring", version = "3.*.*-preview" })
        parameters   = jsonencode({})
        policy_rule  = jsonencode({ if = {}, then = {} })
      }
    ]
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].version == "3.*.*-preview"
    error_message = "Provider-valid wildcard versions must survive unchanged on the resource"
  }
}
