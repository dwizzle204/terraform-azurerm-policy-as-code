resource "terraform_data" "set_assign_replace" {
  input = try(var.initiative.replace_trigger, md5(jsonencode(var.initiative.parameters)))
}

# issue #62: assignment_effect and assignment_parameters are values for
# parameters DECLARED by the assigned initiative. Fail fast when the payload
# would inject undeclared parameter keys, or when assignment_effect is supplied
# without an initiative "effect" parameter wired to at least one member
# reference (e.g. pinned built-ins whose schema is intentionally not hydrated).
resource "terraform_data" "validate_parameter_contract" {
  lifecycle {
    precondition {
      condition     = var.assignment_effect == null || local.initiative_effect_parameter_declared
      error_message = "assignment_effect ('${(var.assignment_effect != null ? var.assignment_effect : "null")}') cannot be applied: the assigned initiative '${try(var.initiative.name, "")}' does not declare an 'effect' parameter. Declare an effect parameter in the initiative schema, omit assignment_effect, or use explicit remediation_reference_ids for unresolved pinned policies (issue #62)."
    }

    precondition {
      # wiring only matters when a remediation task is actually attempted:
      # without an identity (or with remediation skipped) no member is ever
      # selected, so an unwired effect parameter cannot silently no-op (#62)
      condition     = var.assignment_effect == null || var.skip_remediation || length(local.identity_type) == 0 || local.initiative_member_wired_to_effect
      error_message = "assignment_effect ('${(var.assignment_effect != null ? var.assignment_effect : "null")}') cannot be applied: no member reference of initiative '${try(var.initiative.name, "")}' is wired to the initiative-level 'effect' parameter ([parameters('effect')]). Under merge_effects = false members use per-reference effect parameters; supply those via assignment_parameters or omit assignment_effect (issue #62)."
    }

    precondition {
      condition     = length(local.unknown_assignment_parameter_keys) == 0
      error_message = "assignment_parameters contain keys the assigned initiative '${try(var.initiative.name, "")}' does not declare: [${join(", ", local.unknown_assignment_parameter_keys)}]. Declared parameters: [${join(", ", keys(local.initiative_parameters_decoded))}] (issue #62)."
    }
  }
}

resource "azurerm_management_group_policy_assignment" "set" {
  count                = local.assignment_scope.mg
  name                 = local.assignment_name
  display_name         = local.display_name
  description          = local.description
  metadata             = local.metadata
  parameters           = local.parameters
  management_group_id  = var.assignment_scope
  not_scopes           = var.assignment_not_scopes
  enforce              = var.assignment_enforcement_mode
  policy_definition_id = var.initiative.id
  location             = local.assignment_location

  dynamic "non_compliance_message" {
    for_each = var.non_compliance_messages
    content {
      content                        = non_compliance_message.value
      policy_definition_reference_id = non_compliance_message.key == "null" ? null : non_compliance_message.key
    }
  }

  dynamic "identity" {
    for_each = local.identity_type
    content {
      type         = identity.value
      identity_ids = var.identity_ids
    }
  }

  dynamic "overrides" {
    for_each = var.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = coalesce(overrides.value.selectors, [])
        content {
          kind   = try(selectors.value.kind, null)
          in     = try(selectors.value.in, null)
          not_in = try(selectors.value.not_in, null)
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = var.resource_selectors
    content {
      name = try(resource_selectors.value.name, null)
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = try(selectors.value.in, null)
          not_in = try(selectors.value.not_in, null)
        }
      }
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.set_assign_replace]
  }
}

resource "azurerm_subscription_policy_assignment" "set" {
  count                = local.assignment_scope.sub
  name                 = local.assignment_name
  display_name         = local.display_name
  description          = local.description
  metadata             = local.metadata
  parameters           = local.parameters
  subscription_id      = var.assignment_scope
  not_scopes           = var.assignment_not_scopes
  enforce              = var.assignment_enforcement_mode
  policy_definition_id = var.initiative.id
  location             = local.assignment_location

  dynamic "non_compliance_message" {
    for_each = var.non_compliance_messages
    content {
      content                        = non_compliance_message.value
      policy_definition_reference_id = non_compliance_message.key == "null" ? null : non_compliance_message.key
    }
  }

  dynamic "identity" {
    for_each = local.identity_type
    content {
      type         = identity.value
      identity_ids = var.identity_ids
    }
  }

  dynamic "overrides" {
    for_each = var.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = coalesce(overrides.value.selectors, [])
        content {
          kind   = try(selectors.value.kind, null)
          in     = try(selectors.value.in, null)
          not_in = try(selectors.value.not_in, null)
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = var.resource_selectors
    content {
      name = try(resource_selectors.value.name, null)
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = try(selectors.value.in, null)
          not_in = try(selectors.value.not_in, null)
        }
      }
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.set_assign_replace]
  }
}

resource "azurerm_resource_group_policy_assignment" "set" {
  count                = local.assignment_scope.rg
  name                 = local.assignment_name
  display_name         = local.display_name
  description          = local.description
  metadata             = local.metadata
  parameters           = local.parameters
  resource_group_id    = var.assignment_scope
  not_scopes           = var.assignment_not_scopes
  enforce              = var.assignment_enforcement_mode
  policy_definition_id = var.initiative.id
  location             = local.assignment_location

  dynamic "non_compliance_message" {
    for_each = var.non_compliance_messages
    content {
      content                        = non_compliance_message.value
      policy_definition_reference_id = non_compliance_message.key == "null" ? null : non_compliance_message.key
    }
  }

  dynamic "identity" {
    for_each = local.identity_type
    content {
      type         = identity.value
      identity_ids = var.identity_ids
    }
  }

  dynamic "overrides" {
    for_each = var.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = coalesce(overrides.value.selectors, [])
        content {
          kind   = try(selectors.value.kind, null)
          in     = try(selectors.value.in, null)
          not_in = try(selectors.value.not_in, null)
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = var.resource_selectors
    content {
      name = try(resource_selectors.value.name, null)
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = try(selectors.value.in, null)
          not_in = try(selectors.value.not_in, null)
        }
      }
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.set_assign_replace]
  }
}

resource "azurerm_resource_policy_assignment" "set" {
  count                = local.assignment_scope.resource
  name                 = local.assignment_name
  display_name         = local.display_name
  description          = local.description
  metadata             = local.metadata
  parameters           = local.parameters
  resource_id          = var.assignment_scope
  not_scopes           = var.assignment_not_scopes
  enforce              = var.assignment_enforcement_mode
  policy_definition_id = var.initiative.id
  location             = local.assignment_location

  dynamic "non_compliance_message" {
    for_each = var.non_compliance_messages
    content {
      content                        = non_compliance_message.value
      policy_definition_reference_id = non_compliance_message.key == "null" ? null : non_compliance_message.key
    }
  }

  dynamic "identity" {
    for_each = local.identity_type
    content {
      type         = identity.value
      identity_ids = var.identity_ids
    }
  }

  dynamic "overrides" {
    for_each = var.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = coalesce(overrides.value.selectors, [])
        content {
          kind   = try(selectors.value.kind, null)
          in     = try(selectors.value.in, null)
          not_in = try(selectors.value.not_in, null)
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = var.resource_selectors
    content {
      name = try(resource_selectors.value.name, null)
      dynamic "selectors" {
        for_each = resource_selectors.value.selectors
        content {
          kind   = selectors.value.kind
          in     = try(selectors.value.in, null)
          not_in = try(selectors.value.not_in, null)
        }
      }
    }
  }

  lifecycle {
    replace_triggered_by = [terraform_data.set_assign_replace]
  }
}

## role assignments ##
resource "azurerm_role_assignment" "remediation" {
  for_each = {
    for i in local.role_definition_ids :
    # preserve legacy first-segment key when no collision; use hash only for actual collisions
    length([for j in local.role_definition_ids : j if split("-", basename(j))[0] == split("-", basename(i))[0]]) == 1 ? split("-", basename(i))[0] : md5(lower(i)) => i
  }
  scope                            = coalesce(var.role_assignment_scope, var.assignment_scope)
  role_definition_id               = each.value
  principal_id                     = local.assignment.identity[0].principal_id
  skip_service_principal_aad_check = true
}

## aad group memberships ##
resource "azuread_group_member" "remediation" {
  for_each = {
    for i in var.aad_group_remediation_object_ids :
    length([for j in var.aad_group_remediation_object_ids : j if split("-", basename(j))[0] == split("-", basename(i))[0]]) == 1 ? split("-", basename(i))[0] : md5(lower(i)) => i
    if try(local.identity_type.type, "") == "SystemAssigned"
  }
  group_object_id  = each.value
  member_object_id = local.assignment.identity[0].principal_id
}

## remediation tasks ##
resource "terraform_data" "remediation" {
  for_each = { for dr in flatten(values(local.definition_reference)) : dr.reference_id => dr }
  input    = md5(jsonencode(each.key))
}

resource "azurerm_management_group_policy_remediation" "rem" {
  depends_on                     = [azurerm_role_assignment.remediation, azuread_group_member.remediation]
  for_each                       = { for dr in local.definition_reference.mg : dr.reference_id => dr }
  name                           = lower(each.key)
  management_group_id            = local.remediation_scope
  policy_assignment_id           = local.assignment.id
  policy_definition_reference_id = lower(each.key) # https://github.com/hashicorp/terraform-provider-azurerm/issues/18846
  location_filters               = var.location_filters
  failure_percentage             = var.failure_percentage
  parallel_deployments           = var.parallel_deployments
  resource_count                 = var.resource_count

  lifecycle {
    replace_triggered_by = [terraform_data.remediation[each.key]]
    ignore_changes = [
      parallel_deployments,
      resource_count
    ]
  }
}

resource "azurerm_subscription_policy_remediation" "rem" {
  depends_on                     = [azurerm_role_assignment.remediation, azuread_group_member.remediation]
  for_each                       = { for dr in local.definition_reference.sub : dr.reference_id => dr }
  name                           = lower(each.key)
  subscription_id                = local.remediation_scope
  policy_assignment_id           = local.assignment.id
  policy_definition_reference_id = lower(each.key)
  resource_discovery_mode        = local.resource_discovery_mode
  location_filters               = var.location_filters
  failure_percentage             = var.failure_percentage
  parallel_deployments           = var.parallel_deployments
  resource_count                 = var.resource_count

  lifecycle {
    replace_triggered_by = [terraform_data.remediation[each.key]]
    ignore_changes = [
      parallel_deployments,
      resource_count
    ]
  }
}

resource "azurerm_resource_group_policy_remediation" "rem" {
  depends_on                     = [azurerm_role_assignment.remediation, azuread_group_member.remediation]
  for_each                       = { for dr in local.definition_reference.rg : dr.reference_id => dr }
  name                           = lower(each.key)
  resource_group_id              = local.remediation_scope
  policy_assignment_id           = local.assignment.id
  policy_definition_reference_id = lower(each.key)
  resource_discovery_mode        = local.resource_discovery_mode
  location_filters               = var.location_filters
  failure_percentage             = var.failure_percentage
  parallel_deployments           = var.parallel_deployments
  resource_count                 = var.resource_count

  lifecycle {
    replace_triggered_by = [terraform_data.remediation[each.key]]
    ignore_changes = [
      parallel_deployments,
      resource_count
    ]
  }
}

resource "azurerm_resource_policy_remediation" "rem" {
  depends_on                     = [azurerm_role_assignment.remediation, azuread_group_member.remediation]
  for_each                       = { for dr in local.definition_reference.resource : dr.reference_id => dr }
  name                           = lower(each.key)
  resource_id                    = local.remediation_scope
  policy_assignment_id           = local.assignment.id
  policy_definition_reference_id = lower(each.key)
  resource_discovery_mode        = local.resource_discovery_mode
  location_filters               = var.location_filters
  failure_percentage             = var.failure_percentage
  parallel_deployments           = var.parallel_deployments
  resource_count                 = var.resource_count

  lifecycle {
    replace_triggered_by = [terraform_data.remediation[each.key]]
    ignore_changes = [
      parallel_deployments,
      resource_count
    ]
  }
}
