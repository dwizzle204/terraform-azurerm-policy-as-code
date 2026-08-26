mock_provider "azurerm" {
  mock_resource "azurerm_management_group_policy_assignment" {
    defaults        = { id = "/providers/Microsoft.Management/managementGroups/preview/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
    override_during = plan
  }
  mock_resource "azurerm_subscription_policy_assignment" {
    defaults        = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/policyAssignments/mock_initiative" }
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

run "explicit_reference_ids_override_effect_resolution" {
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
    condition     = length(output.remediation_tasks) == 1 && output.remediation_tasks[0].policy_definition_reference_id == "audit_member"
    error_message = "Explicitly listed reference ids are remediated regardless of resolved effect"
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

