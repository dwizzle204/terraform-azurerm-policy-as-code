# Data-driven intent orchestration: definitions -> initiatives -> assignments -> exemptions
# Thin for_each wiring over the existing modules; introduces no new resource types.

locals {
  # reference-integrity is enforced by cross-variable validations on the
  # intent inputs (see variables.tf), which surface as clean plan errors
  # and are assertable via expect_failures in tests.
}

module "definitions" {
  source = "../definition"

  for_each = var.definitions

  file_path       = each.value.file_path
  policy_category = each.value.category
  policy_name     = each.value.policy_name
}

module "initiatives" {
  source = "../initiative"

  for_each = var.initiatives

  initiative_name         = each.key
  initiative_display_name = each.value.display_name
  initiative_description  = each.value.description
  initiative_category     = each.value.category
  management_group_id     = each.value.management_group_id

  member_definitions = [for m in each.value.member_definition_keys : module.definitions[m].definition]
}

module "assignments" {
  source = "../set_assignment"

  for_each = var.assignments

  assignment_scope            = each.value.scope
  assignment_name             = each.value.assignment_name
  assignment_enforcement_mode = each.value.enforcement
  assignment_effect           = each.value.effect
  assignment_parameters       = each.value.parameters
  assignment_not_scopes       = each.value.not_scopes
  assignment_location         = each.value.assignment_location
  skip_remediation            = !each.value.remediate
  role_definition_ids         = each.value.role_definition_ids

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
}
