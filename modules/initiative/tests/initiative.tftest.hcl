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





# issue #59: a custom definition's metadata.version is catalog information
# only and must never be inferred as an Azure definitionVersion selector.
run "custom_metadata_version_not_inferred_as_azure_selector" {
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
    condition     = output.initiative.policy_definition_reference[0].version == null
    error_message = "Custom definition metadata.version must NOT be emitted as an Azure definitionVersion selector"
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].catalog_version == "1.0.0"
    error_message = "Custom metadata.version must remain available as catalog version information"
  }
}

# issue #59: built-in explicit version selectors are preserved unchanged.
run "builtin_explicit_version_selector_preserved" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/providers/Microsoft.Authorization/policyDefinitions/member_w"
        name         = "member_w"
        display_name = "Member W"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters   = jsonencode({})
        policy_rule  = jsonencode({ if = {}, then = {} })
        version      = "3.*.*-preview"
      }
    ]
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].version == "3.*.*-preview"
    error_message = "Explicit built-in version selectors must be preserved unchanged on the reference"
  }
}

# issue #59: built-in explicit three-part selectors pass through as supplied.
run "builtin_explicit_three_part_version_selector_preserved" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/providers/Microsoft.Authorization/policyDefinitions/member_v3"
        name         = "member_v3"
        display_name = "Member V3"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters   = jsonencode({})
        policy_rule  = jsonencode({ if = {}, then = {} })
        version      = "3.1"
      }
    ]
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].version == "3.1"
    error_message = "Explicit built-in '3.1' selectors must be preserved unchanged on the reference"
  }
}

# issue #59: an unversioned built-in emits no definitionVersion selector.
run "unversioned_builtin_version_null" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/providers/Microsoft.Authorization/policyDefinitions/member_none"
        name         = "member_none"
        display_name = "Member None"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters   = jsonencode({})
        policy_rule  = jsonencode({ if = {}, then = {} })
      }
    ]
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].version == null
    error_message = "Unversioned built-ins must emit no definitionVersion selector"
  }
}

# issue #65: literal policy_rule effects must be carried on the reference as a
# normalized declared_effect so assignments can auto-detect remediation
# eligibility without an effect parameter.
run "literal_dine_effect_exposed_as_declared_effect" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/literal_dine"
        name         = "literal_dine"
        display_name = "Literal DINE"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters   = jsonencode({})
        policy_rule = jsonencode({
          if   = { field = "type", equals = "Microsoft.Compute/virtualMachines" }
          then = { effect = "DeployIfNotExists", details = { type = "x" } }
        })
      }
    ]
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].declared_effect == "deployifnotexists"
    error_message = "A literal DeployIfNotExists policy_rule effect must be exposed as declared_effect on the reference (issue #65)"
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].parameter_values == null
    error_message = "A member with no effect parameter must emit no parameter_values effect entry (issue #65)"
  }
}

run "literal_modify_effect_exposed_as_declared_effect" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/literal_modify"
        name         = "literal_modify"
        display_name = "Literal Modify"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters   = jsonencode({})
        policy_rule = jsonencode({
          if   = { field = "type", equals = "Microsoft.Compute/virtualMachines" }
          then = { effect = "Modify" }
        })
      }
    ]
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].declared_effect == "modify"
    error_message = "A literal Modify policy_rule effect must be exposed as declared_effect (issue #65)"
  }
}

run "parameterized_effect_exposed_as_declared_effect" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/parameterized_effect"
        name         = "parameterized_effect"
        display_name = "Parameterized Effect"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters   = jsonencode({ effect = { type = "String", defaultValue = "DeployIfNotExists" } })
        policy_rule = jsonencode({
          if   = { field = "type", equals = "Microsoft.Compute/virtualMachines" }
          then = { effect = "[parameters('effect')]", details = { type = "x" } }
        })
      }
    ]
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].declared_effect == "[parameters('effect')]"
    error_message = "A parameterized policy_rule effect must be exposed as the [parameters('effect')] source (issue #65)"
  }

  assert {
    condition     = jsondecode(output.initiative.policy_definition_reference[0].parameter_values).effect.value == "[parameters('effect')]"
    error_message = "Parameterized members must keep their parameter_values wiring (issue #65)"
  }
}

run "literal_audit_effect_exposed_as_declared_effect" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/literal_audit"
        name         = "literal_audit"
        display_name = "Literal Audit"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters   = jsonencode({})
        policy_rule = jsonencode({
          if   = { field = "type", equals = "Microsoft.Compute/virtualMachines" }
          then = { effect = "Audit" }
        })
      }
    ]
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].declared_effect == "audit"
    error_message = "A literal Audit policy_rule effect must be exposed as declared_effect so it stays excluded from remediation (issue #65)"
  }
}

# issue #65 (oracle P1): a member whose policy rule effect is a LITERAL must not
# get an effect entry in parameter_values even when it declares an effect
# parameter — the declared-but-unused parameter must not be treated as wiring,
# or an assignment effect could fabricate remediation eligibility the policy
# rule never has.
run "literal_rule_effect_does_not_wire_declared_effect_parameter" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/member_lit"
        name         = "member_lit"
        display_name = "Member Lit"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters = jsonencode({
          effect = {
            type          = "String"
            defaultValue  = "Audit"
            allowedValues = ["DeployIfNotExists", "Audit", "Disabled"]
            metadata = {
              displayName = "Effect"
            }
          }
        })
        policy_rule = jsonencode({
          if = { field = "type", equals = "Microsoft.Resources/subscriptions/resources" }
          then = {
            effect = "DeployIfNotExists"
            details = {
              type              = "Microsoft.Insights/diagnosticSettings"
              roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
            }
          }
        })
      }
    ]
  }

  assert {
    condition     = try(jsondecode(output.initiative.policy_definition_reference[0].parameter_values).effect == null, true)
    error_message = "A literal policy rule effect must not be wired to the declared effect parameter; wiring it would let assignment effects fabricate remediation eligibility (issue #65)"
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].declared_effect == "deployifnotexists"
    error_message = "The literal rule effect must still be carried as declared_effect for remediation classification (issue #65)"
  }
}

# issue #65: control — a parameterized rule effect ([parameters('effect')]) IS
# wired: parameter_values must carry the effect mapping.
run "parameterized_rule_effect_remains_wired" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/member_par"
        name         = "member_par"
        display_name = "Member Par"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters = jsonencode({
          effect = {
            type          = "String"
            defaultValue  = "DeployIfNotExists"
            allowedValues = ["DeployIfNotExists", "Audit", "Disabled"]
            metadata = {
              displayName = "Effect"
            }
          }
        })
        policy_rule = jsonencode({
          if = { field = "type", equals = "Microsoft.Resources/subscriptions/resources" }
          then = {
            effect = "[parameters('effect')]"
            details = {
              type              = "Microsoft.Insights/diagnosticSettings"
              roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
            }
          }
        })
      }
    ]
  }

  assert {
    condition     = try(jsondecode(output.initiative.policy_definition_reference[0].parameter_values).effect.value, "") == "[parameters('effect')]"
    error_message = "A parameterized rule effect must remain wired via parameter_values.effect (issue #65)"
  }
}

# issue #65 (Codex P1): a member that DECLARES a REQUIRED effect parameter (no
# defaultValue) but whose rule effect is a literal must KEEP its
# parameter_values.effect mapping — Azure requires every non-defaulted
# referenced-policy parameter to receive a value at initiative construction,
# whether or not the rule consumes it. The mapping is contract satisfaction
# only: effect_parameter_wired stays false so an assignment effect cannot
# fabricate remediation eligibility.
run "required_effect_parameter_mapping_preserved_for_literal_rule" {
  command = plan

  variables {
    member_definitions = [
      {
        id           = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyDefinitions/member_req"
        name         = "member_req"
        display_name = "Member Req"
        mode         = "All"
        metadata     = jsonencode({ category = "Monitoring" })
        parameters = jsonencode({
          effect = {
            type          = "String"
            allowedValues = ["DeployIfNotExists", "Audit", "Disabled"]
            metadata = {
              displayName = "Effect"
            }
          }
        })
        policy_rule = jsonencode({
          if = { field = "type", equals = "Microsoft.Resources/subscriptions/resources" }
          then = {
            effect = "DeployIfNotExists"
            details = {
              type              = "Microsoft.Insights/diagnosticSettings"
              roleDefinitionIds = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
            }
          }
        })
      }
    ]
  }

  assert {
    condition     = try(jsondecode(output.initiative.policy_definition_reference[0].parameter_values).effect.value, "") == "[parameters('effect')]"
    error_message = "A required (no defaultValue) effect parameter must keep its parameter_values.effect mapping so Azure accepts the initiative (issue #65 Codex P1)"
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].effect_parameter_wired == false
    error_message = "A literal rule effect must keep effect_parameter_wired=false even when the required mapping is preserved (issue #65 Codex P1)"
  }

  assert {
    condition     = output.initiative.policy_definition_reference[0].declared_effect == "deployifnotexists"
    error_message = "The literal rule effect must remain the declared_effect used for remediation classification (issue #65)"
  }
}
