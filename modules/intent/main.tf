# Data-driven intent orchestration: definitions -> initiatives -> assignments -> exemptions
# Thin for_each wiring over the existing modules; introduces no new resource types.

locals {
  # reference-integrity is enforced by cross-variable validations on the
  # intent inputs (see variables.tf), which surface as clean plan errors
  # and are assertable via expect_failures in tests.

  # split custom and built-in definitions (built-ins are referenced, not created)
  custom_definitions = {
    for k, v in var.definitions : k => v
    if coalesce(v.source, "custom") == "custom"
  }
  builtin_definitions = {
    for k, v in var.definitions : k => v
    if coalesce(v.source, "custom") == "builtin"
  }
  builtin_definitions_for_data = {
    for k, v in local.builtin_definitions : k => v
    if v.version == null
  }

  # Hydrate built-ins via AzureRM data source so mode/parameters/policy_rule remain faithful
  # Pinned built-ins: when version is explicitly set, do not treat the data
  # source's current definition data as authoritative for that version.
  builtin_definition_objects = {
    for k, v in local.builtin_definitions : k => {
      id                  = try(data.azurerm_policy_definition.builtin[k].id, v.definition_id)
      name                = try(data.azurerm_policy_definition.builtin[k].name, try(basename(v.definition_id), k))
      display_name        = try(data.azurerm_policy_definition.builtin[k].display_name, null)
      description         = try(data.azurerm_policy_definition.builtin[k].description, null)
      mode                = v.mode != null ? v.mode : v.version != null ? null : try(data.azurerm_policy_definition.builtin[k].mode, "All")
      management_group_id = try(data.azurerm_policy_definition.builtin[k].management_group_id, null)
      metadata            = v.metadata != null ? jsonencode(try(jsondecode(v.metadata), v.metadata)) : v.version != null ? null : try(data.azurerm_policy_definition.builtin[k].metadata, null)
      parameters          = v.parameters != null ? jsonencode(try(jsondecode(v.parameters), v.parameters)) : v.version != null ? null : try(data.azurerm_policy_definition.builtin[k].parameters, null)
      policy_rule         = v.policy_rule != null ? jsonencode(try(jsondecode(v.policy_rule), v.policy_rule)) : v.version != null ? null : try(data.azurerm_policy_definition.builtin[k].policy_rule, null)
      version             = v.version
    }
  }

  # management-group scope resolution for custom member definitions (#13 review).
  # An explicit definition scope is required when references disagree.
  definition_scope_conflicts = [
    for k, v in local.custom_definitions : k
    if v.management_group_id == null && (
      length(distinct([
        for initiative in var.initiatives : initiative.management_group_id
        if initiative.management_group_id != null && contains(initiative.member_definition_keys, k)
      ])) > 1 ||
      (
        length([
          for initiative in var.initiatives : 1
          if initiative.management_group_id != null && contains(initiative.member_definition_keys, k)
          ]) > 0 && length([
          for initiative in var.initiatives : 1
          if initiative.management_group_id == null && contains(initiative.member_definition_keys, k)
        ]) > 0
      )
    )
  ]
  definition_management_group = {
    for k, v in local.custom_definitions : k => try(coalesce(
      v.management_group_id,
      try([for ini in var.initiatives : ini.management_group_id if ini.management_group_id != null && contains(ini.member_definition_keys, k)][0], null)
    ), null)
  }

  # unified definition map for initiative consumption
  all_definitions = merge(
    { for k, m in module.definitions : k => m.definition },
    local.builtin_definition_objects,
  )
}

data "azurerm_policy_definition" "builtin" {
  for_each = local.builtin_definitions_for_data
  name     = basename(each.value.definition_id)
}

resource "terraform_data" "validate_definition_scopes" {
  lifecycle {
    precondition {
      condition     = length(local.definition_scope_conflicts) == 0
      error_message = "Definitions referenced by initiatives in multiple management groups, or across management-group and subscription scopes, require an explicit management_group_id: ${join(", ", local.definition_scope_conflicts)}."
    }
  }
}

module "definitions" {
  source = "../definition"

  for_each = local.custom_definitions

  file_path           = each.value.file_path
  policy_category     = each.value.category
  policy_name         = each.value.policy_name
  management_group_id = local.definition_management_group[each.key]
  policy_metadata     = each.value.metadata
}

module "initiatives" {
  source = "../initiative"

  for_each = var.initiatives

  initiative_name         = each.key
  initiative_display_name = each.value.display_name
  initiative_description  = each.value.description
  initiative_category     = each.value.category
  management_group_id     = each.value.management_group_id
  initiative_scope        = try(each.value.initiative_scope, null)
  initiative_metadata     = each.value.metadata

  member_definitions = [for m in each.value.member_definition_keys : local.all_definitions[m]]
}

module "assignments" {
  source = "../set_assignment"

  for_each = var.assignments

  assignment_scope            = each.value.scope
  assignment_name             = coalesce(each.value.assignment_name, each.key)
  assignment_enforcement_mode = each.value.enforcement
  assignment_effect           = each.value.effect
  assignment_parameters       = each.value.parameters
  assignment_not_scopes       = each.value.not_scopes
  assignment_location         = each.value.assignment_location
  skip_remediation            = !each.value.remediate
  remediate_effects           = each.value.remediate_effects
  remediation_reference_ids   = each.value.remediation_reference_ids
  role_definition_ids         = each.value.role_definition_ids
  assignment_metadata         = each.value.metadata
  # Intent has no legacy naming compatibility requirement; always prevent
  # assignment collisions with a deterministic hash suffix.
  collision_resistant_naming = true

  initiative = module.initiatives[each.value.initiative_key].initiative
}

module "exemptions" {
  source = "../exemption"

  for_each = var.exemptions

  name                            = each.value.name
  display_name                    = each.value.display_name
  description                     = each.value.description
  scope                           = each.value.scope
  policy_assignment_id            = module.assignments[each.value.assignment_key].id
  policy_definition_reference_ids = each.value.policy_reference_ids
  exemption_category              = each.value.category
  expires_on                      = each.value.expires_on
  governed                        = try(each.value.governed, null)
  metadata                        = try(each.value.metadata, null)
}
