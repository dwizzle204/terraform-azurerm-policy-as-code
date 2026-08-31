mock_provider "azurerm" {
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/preview/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_initiative", identity = { principal_id = "22222222-2222-2222-2222-222222222222", tenant_id = "33333333-3333-3333-3333-333333333333", type = "SystemAssigned" } }
    override_during = plan
  }
  mock_resource "azurerm_resource_group_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
  mock_resource "azurerm_resource_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1/providers/Microsoft.Compute/virtualMachines/vm-1/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
}

mock_provider "azuread" {}

variables {
  assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000"
  initiative = {
    id                          = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policySetDefinitions/mock_initiative"
    name                        = "mock_initiative"
    display_name                = "Mock Initiative"
    description                 = "Mock"
    management_group_id         = null
    parameters                  = {}
    metadata                    = jsonencode({ category = "Mock" })
    role_definition_ids         = []
    replace_trigger             = "abc"
    policy_definition_reference = []
  }
}

run "subscription_scope_selects_subscription_assignment" {
  command = plan

  assert {
    condition     = output.id == "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_initiative"
    error_message = "A subscription scope must create the subscription-scoped assignment resource"
  }
}

run "management_group_scope_selects_mg_assignment_and_trims_name" {
  command = plan

  variables {
    assignment_scope = "/providers/Microsoft.Management/managementGroups/preview"
    initiative       = merge(var.initiative, { name = "this_initiative_name_is_longer_than_twenty_four" })
  }

  assert {
    condition     = startswith(output.id, "/providers/Microsoft.Management/managementGroups/")
    error_message = "An MG scope must create the MG-scoped assignment resource"
  }

  assert {
    condition     = output.assignment_name == "this_initiative_name_is_" && length(output.assignment_name) == 24
    error_message = "Assignment names at MG scope must be lowercased and trimmed to 24 chars"
  }
}

run "resource_group_scope_selects_rg_assignment" {
  command = plan

  variables {
    assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1"
  }

  assert {
    condition     = endswith(output.id, "resourceGroups/rg-1/providers/Microsoft.Authorization/policyAssignments/mock_initiative")
    error_message = "An RG scope must create the RG-scoped assignment resource"
  }
}

run "no_identity_means_no_remediation_or_principal" {
  command = plan

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "Remediation tasks require a managed identity"
  }

  assert {
    condition     = output.principal_id == null
    error_message = "No managed identity means no principal id"
  }
}

run "identity_and_dine_reference_creates_remediation" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1
    error_message = "A DINE member with SystemAssigned identity should produce one remediation task"
  }

  assert {
    condition     = output.remediation_tasks[0].policy_definition_reference_id == "dine_member"
    error_message = "Remediation task must reference the DINE member definition"
  }
}

run "skip_remediation_suppresses_remediation_tasks" {
  command = plan

  variables {
    skip_remediation    = true
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member", reference_id = "dine_member", parameter_values = jsonencode({}) }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "skip_remediation=true must suppress remediation tasks"
  }
}

run "assignment_effect_is_merged_into_parameters" {
  command = plan

  variables {
    assignment_effect     = "Audit"
    assignment_parameters = { retentionDays = 90 }
    # issue #62: assignment parameters are values for DECLARED initiative
    # parameters; no identity supplied, so member wiring is not required here
    initiative = merge(var.initiative, {
      parameters = jsonencode({
        effect        = { type = "String", defaultValue = "AuditIfNotExists" }
        retentionDays = { type = "Int", defaultValue = 30 }
      })
    })
  }

  assert {
    condition     = jsondecode(output.parameters)["effect"].value == "Audit" && jsondecode(output.parameters)["retentionDays"].value == 90
    error_message = "assignment_effect must merge into parameter values alongside explicit parameters"
  }
}

run "resource_scope_selects_resource_assignment" {
  command = plan

  variables {
    assignment_scope = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-1/providers/Microsoft.Compute/virtualMachines/vm-1"
  }

  assert {
    condition     = endswith(output.id, "virtualMachines/vm-1/providers/Microsoft.Authorization/policyAssignments/mock_initiative")
    error_message = "A resource scope must create the resource-scoped assignment resource"
  }
}

# issue #1/#3: remediation is now effect-filtered and opt-in
run "remediation_tasks_are_now_effect_filtered" {
  # Audit-effect member is NOT eligible even with an explicit DINE/Modify filter
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/audit_member"
          reference_id         = "audit_member"
          parameter_values     = jsonencode({ effect = { value = "Audit" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "Audit-effect members must never receive remediation tasks"
  }
}

run "mixed_effect_initiative_remediates_only_eligible_members" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        },
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/deny_member"
          reference_id         = "deny_member"
          parameter_values     = jsonencode({ effect = { value = "Deny" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "dine_member"
    error_message = "Mixed-effect initiatives must only remediate eligible members"
  }
}

run "default_remediation_is_opt_in" {
  command = plan

  variables {
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member", reference_id = "dine_member", parameter_values = jsonencode({ effect = { value = "DeployIfNotExists" } }) }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "Default (no remediate_effects) must create zero remediation tasks - remediation is opt-in (#3)"
  }
}

# issue #62: enforcementMode = DoNotEnforce must not suppress remediation for an
# eligible member when remediation is explicitly requested.
run "remediation_created_under_do_not_enforce" {
  command = plan

  variables {
    assignment_enforcement_mode = false
    remediate_effects           = ["DeployIfNotExists", "Modify"]
    role_definition_ids         = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member", reference_id = "dine_member", parameter_values = jsonencode({ effect = { value = "DeployIfNotExists" } }) }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_selected_references) == 1 && contains(output.remediation_selected_references, "dine_member")
    error_message = "enforcement=false must still expose an eligible DINE member for remediation (#62)"
  }

  assert {
    condition     = output.enforcement_mode == false
    error_message = "The assignment itself must keep DoNotEnforce while remediation proceeds (#62)"
  }
}

# issue #62: skip_remediation remains an unconditional suppression path.
run "do_not_enforce_with_skip_remediation_still_suppresses" {
  command = plan

  variables {
    assignment_enforcement_mode = false
    skip_remediation            = true
    remediate_effects           = ["DeployIfNotExists", "Modify"]
    role_definition_ids         = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member", reference_id = "dine_member", parameter_values = jsonencode({ effect = { value = "DeployIfNotExists" } }) }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_selected_references) == 0
    error_message = "skip_remediation must suppress remediation even under DoNotEnforce (#62)"
  }
}

# issue #62: Audit members never become remediable, regardless of enforcement.
run "audit_member_under_do_not_enforce_still_not_remediable" {
  command = plan

  variables {
    assignment_enforcement_mode = false
    remediate_effects           = ["DeployIfNotExists", "Modify"]
    role_definition_ids         = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/audit_member", reference_id = "audit_member", parameter_values = jsonencode({ effect = { value = "Audit" } }) }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_selected_references) == 0
    error_message = "Audit must never be remediable regardless of enforcement mode (#62)"
  }
}

run "explicit_reference_ids_reject_known_non_remediable_effect" {
  command = plan

  variables {
    remediate_effects         = []
    remediation_reference_ids = ["audit_member"]
    role_definition_ids       = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/audit_member"
          reference_id         = "audit_member"
          parameter_values     = jsonencode({ effect = { value = "Audit" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "Explicitly listed Audit references must not bypass remediation effect safety"
  }
}

run "legacy_parity_with_explicit_filter" {
  # migration parity: setting the filter reproduces pre-change task counts
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    skip_remediation    = false
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/m1", reference_id = "m1", parameter_values = jsonencode({ effect = { value = "DeployIfNotExists" } }) },
        { policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/m2", reference_id = "m2", parameter_values = jsonencode({ effect = { value = "DeployIfNotExists" } }) }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 2
    error_message = "Legacy parity: two eligible members produce two remediation tasks when the filter is configured"
  }
}

# ---- #2: collision-resistant naming (opt-in) ----

run "collision_resistant_names_differ_for_shared_prefixes" {
  command = plan

  variables {
    collision_resistant_naming = true
    assignment_scope           = "/providers/Microsoft.Management/managementGroups/preview"
    assignment_name            = "platform_baseline_security_initiative_rollout_a"
  }

  assert {
    condition     = startswith(output.assignment_name, format("%s-", substr(lower(var.assignment_name), 0, 15)))
    error_message = "Name should be the truncated lowercase prefix followed by '-' and the deterministic hash"
  }

  assert {
    condition     = length(output.assignment_name) <= 24
    error_message = "MG-scope names must stay within the 24 character Azure limit in collision-resistant mode"
  }
}

run "collision_resistant_names_differ_between_logical_identities" {
  command = plan

  variables {
    collision_resistant_naming = true
    initiative                 = merge(var.initiative, { name = "platform_baseline_security_initiative_rollout_b" })
  }

  assert {
    condition     = output.assignment_name != run.collision_resistant_names_differ_for_shared_prefixes.assignment_name
    error_message = "Two logical identities sharing a >24 character prefix must not collide"
  }
}

run "collision_resistant_names_stable_baseline" {
  command = plan

  variables {
    collision_resistant_naming = true
  }
}

# literal cross-run equality: identical inputs must produce the identical name
run "collision_resistant_names_stable" {
  command = plan

  variables {
    collision_resistant_naming = true
  }

  assert {
    condition     = output.assignment_name == run.collision_resistant_names_stable_baseline.assignment_name
    error_message = "Identical inputs must produce the identical collision-resistant assignment name across runs"
  }

  assert {
    condition     = length(output.assignment_name) <= 64
    error_message = "Subscription-scope collision-resistant names stay within the 64-char Azure limit"
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

run "collision_resistant_mg_24_char_limit" {
  command = plan

  variables {
    collision_resistant_naming = true
    assignment_scope           = "/providers/Microsoft.Management/managementGroups/preview"
    initiative                 = merge(var.initiative, { name = "this_initiative_name_is_longer_than_twenty_four" })
  }

  assert {
    condition     = length(output.assignment_name) == 24 && can(regex("^[a-z0-9_-]{15}-[0-9a-f]{8}$", output.assignment_name))
    error_message = "MG scope: 15-char prefix + '-' + 8-char hash = exactly 24 characters"
  }
}

# BLOCKER FIX 2: consumer-reality regression — effects exactly as produced by
# the initiative module and the real policies library.

run "consumer_reality_interpolated_effect_resolves_via_default" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      parameters = jsondecode(file("tests/fixtures/deploy_keyvault_diagnostic_setting.json")).properties.parameters
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/deploy_keyvault_diagnostic_setting"
          reference_id         = "deploy_keyvault_diagnostic_setting"
          parameter_values     = jsonencode({ effect = { value = "[parameters('effect')]" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "deploy_keyvault_diagnostic_setting"
    error_message = "Interpolated [parameters('effect')] must resolve to the member default (DeployIfNotExists) and create a remediation task"
  }
}

run "library_sweep_classifies_real_policy_forms" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    # the lowercase-literal member carries its effect only in policyRule.then.effect,
    # which is not part of the initiative reference contract -> explicitly selected
    remediation_reference_ids = ["preview_deploy_linux_azure_monitor_vm_agent"]
    initiative = merge(var.initiative, {
      # merged initiative parameter schema (as produced by module.initiative)
      parameters = jsondecode(file("tests/fixtures/deploy_keyvault_diagnostic_setting.json")).properties.parameters
      policy_definition_reference = [
        {
          # interpolated form, resolves via merged schema defaultValue
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/deploy_keyvault_diagnostic_setting"
          reference_id         = "deploy_keyvault_diagnostic_setting"
          parameters           = jsonencode(jsondecode(file("tests/fixtures/deploy_keyvault_diagnostic_setting.json")).properties.parameters)
          policy_rule          = jsonencode(jsondecode(file("tests/fixtures/deploy_keyvault_diagnostic_setting.json")).properties.policyRule)
          parameter_values     = jsonencode({ effect = { value = "[parameters('effect')]" } })
        },
        {
          # lowercase literal effect lives in policyRule.then.effect (not on the
          # reference); resolved via explicit remediation_reference_ids above
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/deploy_linux_azure_monitor_vm_agent"
          reference_id         = "preview_deploy_linux_azure_monitor_vm_agent"
          parameters           = jsonencode(jsondecode(file("tests/fixtures/preview_deploy_linux_azure_monitor_vm_agent.json")).properties.parameters)
          policy_rule          = jsonencode(jsondecode(file("tests/fixtures/preview_deploy_linux_azure_monitor_vm_agent.json")).properties.policyRule)
          parameter_values     = jsonencode({})
        },
        {
          # explicit literal non-remediable effect (merge_effects=false style)
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/deploy_vnet_diagnostic_setting"
          reference_id         = "deploy_vnet_diagnostic_setting"
          parameters           = jsonencode(jsondecode(file("tests/fixtures/deploy_vnet_diagnostic_setting.json")).properties.parameters)
          policy_rule          = jsonencode(jsondecode(file("tests/fixtures/deploy_vnet_diagnostic_setting.json")).properties.policyRule)
          parameter_values     = jsonencode({ effect = { value = "Audit" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_selected_references) == 2 && contains(output.remediation_selected_references, "deploy_keyvault_diagnostic_setting") && contains(output.remediation_selected_references, "preview_deploy_linux_azure_monitor_vm_agent")
    error_message = "Sweep must select interpolated-default via resolution and the rule-literal form via explicit selection, excluding the literal Audit member"
  }
}

# FIX 6: assignment-only deployment creates zero identity/RBAC/remediation side effects
run "assignment_only_deploys_without_rbac_or_remediation" {
  command = plan

  assert {
    condition     = output.principal_id == null && length(output.remediation_selected_references) == 0
    error_message = "Assignment-only deployment must have no managed identity and no remediation selections"
  }
}


run "override_selectors_round_trip_with_kinds" {
  command = plan

  variables {
    overrides = [
      {
        value = "Disabled"
        selectors = [
          { kind = "policyDefinitionReferenceId", in = ["member_a"] },
          { kind = "resourceLocation", not_in = ["global"] }
        ]
      }
    ]
  }

  assert {
    condition     = length(azurerm_subscription_policy_assignment.set[0].overrides) == 1
    error_message = "One override should reach the assignment resource"
  }

  assert {
    condition     = length(azurerm_subscription_policy_assignment.set[0].overrides[0].selectors) == 2
    error_message = "All supplied override selectors must be emitted (none dropped)"
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.set[0].overrides[0].value == "Disabled"
    error_message = "Override effect value must round-trip"
  }
}

run "invalid_override_kind_fails_validation" {
  command = plan

  variables {
    overrides = [
      { value = "Audit", selectors = [{ kind = "bogusKind", in = ["x"] }] }
    ]
  }

  expect_failures = [
    var.overrides,
  ]
}

run "multiple_resource_selectors_round_trip" {
  command = plan

  variables {
    resource_selectors = [
      { name = "sdp-phase-1", selectors = [{ kind = "resourceLocation", in = ["canadacentral"] }] },
      { name = "sdp-phase-2", selectors = [{ kind = "resourceType", in = ["Microsoft.Compute/virtualMachines"] }] }
    ]
  }

  assert {
    condition     = length(azurerm_subscription_policy_assignment.set[0].resource_selectors) == 2
    error_message = "Both resource selectors must be emitted"
  }

  assert {
    condition     = length(azurerm_subscription_policy_assignment.set[0].resource_selectors[0].selectors) == 1
    error_message = "Nested selector lists must round-trip intact"
  }
}

run "invalid_resource_selector_kind_fails_validation" {
  command = plan

  variables {
    resource_selectors = [
      { name = "bad", selectors = [{ kind = "notAKind", in = ["x"] }] }
    ]
  }

  expect_failures = [
    var.resource_selectors,
  ]
}

# locks #24 follow-ups: assignment_parameters override precedence and
# unresolvable-effect classification (oracle-verified behaviors, previously
# only probe-tested)

run "assignment_parameters_effect_overrides_default_for_remediability" {
  command = plan

  variables {
    role_definition_ids   = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    remediate_effects     = ["DeployIfNotExists", "Modify"]
    assignment_parameters = { effect = "Modify" }
    initiative = merge(var.initiative, {
      parameters = jsonencode({
        effect = { type = "String", defaultValue = "AuditIfNotExists" }
      })
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/member_with_audit_default"
          reference_id         = "member_with_audit_default"
          parameter_values     = jsonencode({ effect = { value = "[parameters('effect')]" } }) # exact shape module.initiative emits
        }
      ]
    })
  }

  assert {
    condition     = contains(output.remediation_selected_references, "member_with_audit_default")
    error_message = "assignment_parameters effect value must take precedence over the member's defaultValue when determining remediability"
  }
}

run "unresolvable_effect_is_classified_not_remediable" {
  command = plan

  variables {
    role_definition_ids       = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    remediate_effects         = ["DeployIfNotExists", "Modify"]
    remediation_reference_ids = ["member_without_default"]
    initiative = merge(var.initiative, {
      parameters = jsonencode({
        effect = { type = "String" } # no defaultValue, no assignment override -> unresolvable
      })
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/member_without_default"
          reference_id         = "member_without_default"
          parameter_values     = jsonencode({ effect = { value = "[parameters('effect')]" } })
        }
      ]
    })
  }

  assert {
    condition     = contains(output.remediation_selected_references, "member_without_default")
    error_message = "Explicit references may select members whose effect cannot be resolved"
  }
}

run "assignment_effect_override_makes_audit_member_eligible" {
  command = plan

  variables {
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    assignment_effect   = "Modify"
    initiative = merge(var.initiative, {
      parameters = jsonencode({
        effect = { type = "String", defaultValue = "Audit" }
      })
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/member_with_audit_default"
          reference_id         = "member_with_audit_default"
          parameter_values     = jsonencode({ effect = { value = "[parameters('effect')]" } })
        }
      ]
    })
  }

  assert {
    condition     = contains(output.remediation_selected_references, "member_with_audit_default")
    error_message = "assignment_effect = Modify should make an Audit-default member eligible for remediation"
  }
}

run "group_membership_permission_path_creates_remediation" {
  command = plan

  variables {
    aad_group_remediation_object_ids = ["11111111-1111-1111-1111-111111111111"]
    remediate_effects                = ["DeployIfNotExists"]
    initiative = merge(var.initiative, {
      role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
      policy_definition_reference = [{
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/group_test"
        reference_id         = "group_test"
        parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
      }]
    })
  }

  assert {
    condition     = length(resource.azuread_group_member.remediation) == 1
    error_message = "Group-based permission provisioning must create the group membership prerequisite"
  }

  assert {
    condition     = length(output.remediation_tasks) > 0
    error_message = "Group-based permission provisioning must retain remediation creation"
  }

}

run "role_assignment_permission_path_creates_remediation" {
  command = plan

  variables {
    aad_group_remediation_object_ids = []
    role_definition_ids              = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    remediate_effects                = ["DeployIfNotExists"]
    initiative = merge(var.initiative, {
      role_definition_ids = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
      policy_definition_reference = [{
        policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/role_test"
        reference_id         = "role_test"
        parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
      }]
    })
  }

  assert {
    condition     = length(resource.azurerm_role_assignment.remediation) == 1
    error_message = "Role-assignment permission provisioning must create the RBAC prerequisite"
  }

  assert {
    condition     = length(output.remediation_tasks) > 0
    error_message = "Role-assignment permission provisioning must retain remediation creation"
  }

}


# issue #62: assignment_effect without a declared initiative "effect" parameter
# (schema-less pinned built-in) must fail fast before provider apply.
run "assignment_effect_without_effect_param_fails" {
  command = plan

  variables {
    assignment_effect   = "DeployIfNotExists"
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    # default initiative fixture declares parameters = {} — no effect parameter
  }

  expect_failures = [
    terraform_data.validate_parameter_contract,
  ]
}

# issue #65: assignment_effect only reaches members wired to
# [parameters('effect')]. An unwired member with a resolvable literal effect of
# its own keeps that effect — here assignment_effect is inert and the literal
# DINE member is still selected for remediation.
run "assignment_effect_unwired_member_classified_by_own_effect" {
  command = plan

  variables {
    assignment_effect   = "DeployIfNotExists"
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      parameters = jsonencode({
        effect = { type = "String", defaultValue = "Audit" }
      })
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/member_literal_effect"
          reference_id         = "member_literal_effect"
          # literal effect: NOT wired to the initiative-level effect parameter
          parameter_values = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "member_literal_effect"
    error_message = "An unwired member with its own literal DINE effect must keep that effect and be remediated; assignment_effect cannot reclassify it (issue #65)"
  }
}

# issue #62: unknown assignment_parameters keys must fail fast naming the key.
run "assignment_parameters_unknown_key_fails" {
  command = plan

  variables {
    assignment_parameters = { retentionDaysTypo = 90 }
    initiative = merge(var.initiative, {
      parameters = jsonencode({
        retentionDays = { type = "Int", defaultValue = 30 }
      })
    })
  }

  expect_failures = [
    terraform_data.validate_parameter_contract,
  ]
}

# issue #62: declared effect parameter + wired member reference: assignment_effect
# flows into the normalized payload AND drives remediation selection.
run "assignment_effect_declared_param_payload_and_selection" {
  command = plan

  variables {
    assignment_effect   = "Modify"
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      parameters = jsonencode({
        effect = { type = "String", defaultValue = "Audit" }
      })
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/member_with_audit_default"
          reference_id         = "member_with_audit_default"
          parameter_values     = jsonencode({ effect = { value = "[parameters('effect')]" } })
        }
      ]
    })
  }

  assert {
    condition     = try(jsondecode(output.parameters)["effect"].value, "") == "Modify"
    error_message = "assignment_effect must be wired into the normalized payload when the initiative declares an 'effect' parameter (#62)"
  }

  assert {
    condition     = contains(output.remediation_selected_references, "member_with_audit_default")
    error_message = "assignment_effect with a declared, wired effect parameter must drive remediation selection (#62)"
  }
}

# ---- issue #65: per-member effective effect ----

# assignment_effect must only override members wired to [parameters('effect')].
# A mixed initiative with one wired DINE member and one unwired literal Audit
# member must not have the unwired member's effect replaced.
run "assignment_effect_applies_only_to_wired_members" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    assignment_effect   = "DeployIfNotExists"
    initiative = merge(var.initiative, {
      parameters = { effect = { type = "String", defaultValue = "Audit" } }
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/wired_dine"
          reference_id         = "wired_dine"
          parameter_values     = jsonencode({ effect = { value = "[parameters('effect')]" } })
        },
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/unwired_audit"
          reference_id         = "unwired_audit"
          parameter_values     = jsonencode({ effect = { value = "Audit" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "wired_dine"
    error_message = "assignment_effect must only reach the member wired to [parameters('effect')]; the unwired Audit member must stay Audit and receive no task (issue #65)"
  }
}

# the inverse case: an unrelated assignment_effect=Audit must not suppress an
# unwired literal DINE member — unwired members keep their own effect.
run "unwired_literal_dine_not_suppressed_by_assignment_effect" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    assignment_effect   = "Audit"
    initiative = merge(var.initiative, {
      parameters = { effect = { type = "String", defaultValue = "Audit" } }
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/literal_dine"
          reference_id         = "literal_dine"
          declared_effect      = "deployifnotexists"
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "literal_dine"
    error_message = "An unwired literal DINE member must keep its own effect; assignment_effect=Audit must not suppress it (issue #65)"
  }
}

# literal DINE/Modify effects with no effect parameter must be auto-detected
# for remediation via the reference's declared_effect (no assignment_effect,
# no explicit remediation_reference_ids).
run "literal_dine_member_auto_detected_for_remediation" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/literal_dine"
          reference_id         = "literal_dine"
          declared_effect      = "deployifnotexists"
        },
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/literal_audit"
          reference_id         = "literal_audit"
          declared_effect      = "audit"
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "literal_dine"
    error_message = "A literal DINE member with no effect parameter must be auto-selected for remediation while literal Audit stays excluded (issue #65)"
  }
}

run "literal_modify_member_auto_detected_for_remediation" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/literal_modify"
          reference_id         = "literal_modify"
          declared_effect      = "modify"
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "literal_modify"
    error_message = "A literal Modify member with no effect parameter must be auto-selected for remediation (issue #65)"
  }
}

# an unwired member with no resolvable effect of its own cannot be rescued by
# assignment_effect: the plan must fail naming the orphan member.
run "assignment_effect_orphan_member_fails_fast" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    assignment_effect   = "DeployIfNotExists"
    initiative = merge(var.initiative, {
      parameters = { effect = { type = "String", defaultValue = "Audit" } }
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/orphan_member"
          reference_id         = "orphan_member"
          declared_effect      = ""
        }
      ]
    })
  }

  expect_failures = [
    terraform_data.validate_parameter_contract,
  ]
}

# ---- issue #65: policyEffect overrides ----

# a reference-scoped override to Audit suppresses remediation for exactly the
# selected member; unselected DINE members are unaffected.
run "reference_scoped_override_suppresses_selected_member" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    overrides = [
      {
        value     = "Audit"
        selectors = [{ kind = "policyDefinitionReferenceId", in = ["dine_member"] }]
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        },
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member_two"
          reference_id         = "dine_member_two"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "dine_member_two"
    error_message = "A DINE member overridden to Audit must not receive a remediation task; unaffected members keep theirs (issue #65)"
  }
}

# Multiple reference selectors are ANDed by Azure. A contradictory in/not_in
# pair must not apply its policyEffect override to the member.
run "contradictory_reference_selectors_do_not_match" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    overrides = [
      {
        value = "Audit"
        selectors = [
          { kind = "policyDefinitionReferenceId", in = ["dine_member"] },
          { kind = "policyDefinitionReferenceId", not_in = ["dine_member"] },
        ]
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1
    error_message = "Contradictory reference selectors must not suppress the DINE member (issue #65)"
  }
}

# a location-scoped non-remediable override makes the effective effect
# resource-dependent: automatic selection is suppressed entirely.
run "location_scoped_override_suppresses_automatic_selection" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    overrides = [
      {
        value     = "Audit"
        selectors = [{ kind = "resourceLocation", in = ["westeurope"] }]
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "A location-scoped non-remediable override makes the effect resource-dependent; automatic remediation must be suppressed (issue #65)"
  }
}

# the conservative suppression is overridable via explicit remediation_reference_ids
run "location_scoped_override_explicit_reference_still_selects" {
  command = plan

  variables {
    remediate_effects         = ["DeployIfNotExists", "Modify"]
    role_definition_ids       = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    remediation_reference_ids = ["dine_member"]
    overrides = [
      {
        value     = "Audit"
        selectors = [{ kind = "resourceLocation", in = ["westeurope"] }]
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "dine_member"
    error_message = "Explicit remediation_reference_ids remain the opt-in path when override ambiguity suppresses automatic selection (issue #65)"
  }
}

# issue #65 (oracle blocker): a MIXED override (referenceId + resourceLocation)
# is resource-dependent even though its value is remediable: automatic
# selection must be suppressed for the selected member.
run "mixed_reference_location_override_suppresses_automatic_selection" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    overrides = [
      {
        value = "DeployIfNotExists"
        selectors = [
          { kind = "policyDefinitionReferenceId", in = ["dine_member"] },
          { kind = "resourceLocation", in = ["westeurope"] }
        ]
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "A mixed referenceId+resourceLocation override is resource-dependent; automatic remediation must be suppressed even for a remediable override value (issue #65)"
  }
}

# issue #65 (oracle blocker): a location-scoped override whose value is itself
# remediable (DeployIfNotExists) is still resource-dependent and must suppress
# automatic selection — the old logic only flagged 4 hard-coded non-remediable
# values and let location-scoped DINE/Modify through as static.
run "location_scoped_remendiable_value_override_suppresses_automatic_selection" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    overrides = [
      {
        value     = "Modify"
        selectors = [{ kind = "resourceLocation", in = ["westeurope"] }]
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "A location-scoped override with a remediable value is still resource-dependent; automatic remediation must be suppressed (issue #65)"
  }
}

# issue #65: ambiguity is waived when location_filters prove the override cannot
# touch the remediated resources: the override scopes by `in` and none of those
# locations intersects location_filters.
run "location_override_disjoint_from_location_filters_is_provable" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    location_filters    = ["northeurope"]
    overrides = [
      {
        value     = "Audit"
        selectors = [{ kind = "resourceLocation", in = ["westeurope"] }]
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "dine_member"
    error_message = "A location-scoped override whose `in` locations are disjoint from location_filters cannot affect the remediated resources; automatic selection must proceed (issue #65)"
  }
}

# issue #65: an empty-selector override (no selectors at all) is an
# unconditional GLOBAL override: its value replaces every member's effect.
run "empty_selector_override_is_unconditional_global" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    overrides = [
      {
        value     = "Audit"
        selectors = []
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        },
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member_two"
          reference_id         = "dine_member_two"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 0
    error_message = "An empty-selector override is an unconditional global override; every member's effect becomes Audit and no remediation tasks may be created (issue #65)"
  }
}

# issue #65 (oracle P1): a MIXED override (referenceId + resourceLocation) whose
# location selector is provably disjoint from location_filters cannot apply to
# ANY remediated resource (Azure ANDs all selectors). Its policyEffect value
# must not replace the member effect even though the referenceId selector
# matches — the waiver must exclude the override entirely, not merely clear the
# ambiguity flag while still applying its value.
run "mixed_disjoint_location_override_value_does_not_apply" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    location_filters    = ["northeurope"]
    overrides = [
      {
        value = "Audit"
        selectors = [
          { kind = "policyDefinitionReferenceId", in = ["dine_member"] },
          { kind = "resourceLocation", in = ["westeurope"] }
        ]
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "dine_member"
    error_message = "A mixed override whose resourceLocation selector is disjoint from location_filters must be excluded entirely; its value must not replace the member's remediable effect (issue #65)"
  }
}

# issue #65 (oracle P1): assignment_effect must only reach members actually
# wired to [parameters('effect')]. A member whose initiative reference carries
# no effect mapping (literal rule effect, e.g. Audit) keeps its own effect and
# is never rescued into remediation by an unrelated assignment-level effect.
run "assignment_effect_does_not_rescue_unwired_literal_member" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    assignment_effect   = "DeployIfNotExists"
    initiative = merge(var.initiative, {
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
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "[parameters('effect')]" } })
        },
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/audit_member"
          reference_id         = "audit_member"
          declared_effect      = "audit"
          parameter_values     = null
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "dine_member"
    error_message = "assignment_effect must remediate only the wired member; an unwired literal Audit member keeps its own effect and must not be remediated (issues #62/#65)"
  }
}

# ---- issue #65 (Codex P1): orphan validation must not reject valid opt-outs ----

# remediation is opt-in: with remediate_effects = [] no task is expected, so an
# unresolved unwired member next to a wired one must not fail the assignment.
run "assignment_effect_orphan_not_flagged_when_remediation_opt_out" {
  command = plan

  variables {
    remediate_effects   = []
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    assignment_effect   = "DeployIfNotExists"
    initiative = merge(var.initiative, {
      parameters = { effect = { type = "String", defaultValue = "Audit" } }
      policy_definition_reference = [
        {
          policy_definition_id   = "/providers/Microsoft.Authorization/policyDefinitions/wired_member"
          reference_id           = "wired_member"
          declared_effect        = ""
          effect_parameter_wired = true
          parameter_values       = jsonencode({ effect = { value = "[parameters('effect')]" } })
        },
        {
          policy_definition_id   = "/providers/Microsoft.Authorization/policyDefinitions/orphan_member"
          reference_id           = "orphan_member"
          declared_effect        = ""
          effect_parameter_wired = false
          parameter_values       = null
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_selected_references) == 0
    error_message = "With remediate_effects = [] no remediation tasks are expected, so the assignment must plan cleanly (issue #65 Codex P1)"
  }
}

# An assignment effect that is not among requested remediation effects cannot
# select a task, so unresolved members must not trigger orphan validation.
run "assignment_effect_orphan_not_flagged_when_effect_not_requested" {
  command = plan

  variables {
    remediate_effects   = ["Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    assignment_effect   = "Audit"
    initiative = merge(var.initiative, {
      parameters = { effect = { type = "String", defaultValue = "Audit" } }
      policy_definition_reference = [
        {
          policy_definition_id   = "/providers/Microsoft.Authorization/policyDefinitions/orphan_member"
          reference_id           = "orphan_member"
          declared_effect        = ""
          effect_parameter_wired = false
          parameter_values       = null
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_selected_references) == 0
    error_message = "An Audit assignment must not activate orphan validation when only Modify is requested (issue #65)"
  }
}

# a policyEffect override that RESOLVES the previously unresolved member means
# assignment_effect needs no rescue: the guard must not fire.
run "assignment_effect_orphan_not_flagged_when_override_resolves" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    assignment_effect   = "DeployIfNotExists"
    overrides = [
      {
        value     = "DeployIfNotExists"
        selectors = [{ kind = "policyDefinitionReferenceId", in = ["orphan_member"] }]
      }
    ]
    initiative = merge(var.initiative, {
      parameters = { effect = { type = "String", defaultValue = "Audit" } }
      policy_definition_reference = [
        {
          policy_definition_id   = "/providers/Microsoft.Authorization/policyDefinitions/wired_member"
          reference_id           = "wired_member"
          declared_effect        = ""
          effect_parameter_wired = true
          parameter_values       = jsonencode({ effect = { value = "[parameters('effect')]" } })
        },
        {
          policy_definition_id   = "/providers/Microsoft.Authorization/policyDefinitions/orphan_member"
          reference_id           = "orphan_member"
          declared_effect        = ""
          effect_parameter_wired = false
          parameter_values       = null
        }
      ]
    })
  }

  assert {
    condition     = contains(output.remediation_selected_references, "orphan_member")
    error_message = "An override-resolved member must be selected for remediation without triggering the orphan fail-fast (issue #65 Codex P1)"
  }
}

# a required-but-unconsumed effect mapping (effect_parameter_wired=false with a
# parameter_values.effect entry) must NOT let assignment_effect fabricate
# remediation eligibility for a literal Audit rule.
run "assignment_effect_does_not_rescue_required_mapping_unwired_member" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists", "Modify"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    assignment_effect   = "DeployIfNotExists"
    initiative = merge(var.initiative, {
      parameters = { effect = { type = "String" } }
      policy_definition_reference = [
        {
          policy_definition_id   = "/providers/Microsoft.Authorization/policyDefinitions/lit_audit_member"
          reference_id           = "lit_audit_member"
          declared_effect        = "audit"
          effect_parameter_wired = false
          parameter_values       = jsonencode({ effect = { value = "[parameters('effect')]" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_selected_references) == 0
    error_message = "A preserved required effect mapping must not reclassify a literal Audit member as remediable via assignment_effect (issue #65 Codex P1)"
  }
}

# Contradictory reference selectors cannot jointly select a member. Even when
# paired with a resourceLocation selector, they must not make the member's
# effect ambiguous or suppress its otherwise eligible remediation.
run "contradictory_reference_selectors_are_not_location_ambiguous" {
  command = plan

  variables {
    remediate_effects   = ["DeployIfNotExists"]
    role_definition_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
    location_filters    = ["westeurope"]
    overrides = [
      {
        value = "Audit"
        selectors = [
          { kind = "policyDefinitionReferenceId", in = ["dine_member"] },
          { kind = "policyDefinitionReferenceId", not_in = ["dine_member"] },
          { kind = "resourceLocation", in = ["westeurope"] }
        ]
      }
    ]
    initiative = merge(var.initiative, {
      policy_definition_reference = [
        {
          policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/dine_member"
          reference_id         = "dine_member"
          parameter_values     = jsonencode({ effect = { value = "DeployIfNotExists" } })
        }
      ]
    })
  }

  assert {
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "dine_member"
    error_message = "Contradictory reference selectors must not suppress remediation as a location-ambiguous override"
  }
}
