# CAF Landing Zone reference implementation (see README.md for the model).
#
# One modules/intent root declares every policy intent:
#   - built-in definitions are shared across initiatives (built-ins are
#     referenced by ARM ID, never created, so they are safe to reuse)
#   - each management group gets its own initiative because initiatives are
#     created AT the scope they name; an initiative created at Platform cannot
#     be assigned to a sibling Landing zones management group
#   - each management group gets its own assignment with deliberately
#     different governance intent

locals {
  # Microsoft built-ins used by this example. Unpinned built-ins are hydrated
  # from the Azure environment at plan time (effect, parameters, mode and
  # roleDefinitionIds), so the Platform DINE assignment gets a real identity /
  # RBAC path without this example copying Microsoft's rule JSON.
  builtins = {
    # Deploy network watcher when a new virtual network is created (DINE)
    network_watcher_dine = {
      source        = "builtin"
      definition_id = "/providers/Microsoft.Authorization/policyDefinitions/a9b99f8f-538b-4daf-99e2-286e76c855c4"
      metadata      = { controlIds = ["AZ-PLAT-001"], owner = "platform-team", stage = "enforced" }
    }
    # Allowed locations (parameterized deny/audit control)
    allowed_locations = {
      source        = "builtin"
      definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01973c11"
      metadata      = { controlIds = ["AZ-LZ-001", "AZ-SBX-001"], owner = "platform-team", stage = "guardrail" }
    }
  }
}

module "policy_intent" {
  # in-repo example: always use the local module source.
  # External consumers should pin this repository by git ref instead of using
  # the upstream registry module (see IMPLEMENTATION_GUIDE.md).
  source = "../../modules/intent"

  definitions = local.builtins

  initiatives = {
    # A. Platform - shared platform services. DINE/Modify + remediation is
    #    meaningful here: the platform team owns remediation end to end.
    platform_baseline = {
      display_name           = "Platform Baseline"
      description            = "Platform-owned deploy-if-not-exists controls with managed identity, RBAC and remediation."
      category               = "Platform"
      management_group_id    = var.platform_management_group_id
      member_definition_keys = ["network_watcher_dine"]
      metadata = {
        controlIds = ["AZ-PLAT-001"]
        owner      = "platform-team"
        stage      = "enforced"
      }
    }

    # B. Landing zones - workload guardrails inherited by every application
    #    subscription placed under this management group. Enforced Deny.
    landing_zones_guardrails = {
      display_name           = "Landing Zones Guardrails"
      description            = "Workload guardrails enforced for all application landing zones."
      category               = "Landing Zones"
      management_group_id    = var.landing_zones_management_group_id
      member_definition_keys = ["allowed_locations"]
      metadata = {
        controlIds = ["AZ-LZ-001"]
        owner      = "platform-team"
        stage      = "enforced"
      }
    }

    # C. Sandboxes - deliberately less restrictive, still governed. The same
    #    location control runs in DoNotEnforce mode: violations are visible in
    #    compliance data but requests are not blocked while teams experiment.
    sandboxes_baseline = {
      display_name           = "Sandboxes Baseline"
      description            = "Observe-first posture for experimentation. Still governed, not an escape hatch."
      category               = "Sandboxes"
      management_group_id    = var.sandboxes_management_group_id
      member_definition_keys = ["allowed_locations"]
      metadata = {
        controlIds = ["AZ-SBX-001"]
        owner      = "platform-team"
        stage      = "observe"
      }
    }
  }

  assignments = {
    # A. Platform: remediation is opt-in; DoNotEnforce would NOT stop this
    #    explicitly requested remediation task (Azure supports manual
    #    remediation of DINE policies under DoNotEnforce).
    platform = {
      initiative_key            = "platform_baseline"
      scope                     = var.platform_management_group_id
      assignment_name           = "platform-baseline"
      enforcement               = true
      effect                    = "DeployIfNotExists"
      remediate                 = true
      remediate_effects         = ["DeployIfNotExists", "Modify"]
      remediation_reference_ids = []
      role_definition_ids       = ["/providers/Microsoft.Authorization/roleDefinitions/b24988ac-6180-42a0-ab88-20f7382dd24c"]
      parameters                = {}
      assignment_location       = "westeurope"
      metadata = {
        controlIds = ["AZ-PLAT-001"]
        owner      = "platform-team"
        stage      = "enforced"
      }
    }

    # B. Landing zones: the stricter workload baseline. effect Deny enforced at
    #    request time; inherited by every subscription under this MG.
    landing_zones = {
      initiative_key            = "landing_zones_guardrails"
      scope                     = var.landing_zones_management_group_id
      assignment_name           = "landing-zones-guardrails"
      enforcement               = true
      effect                    = "Deny"
      remediate                 = false
      remediate_effects         = ["DeployIfNotExists", "Modify"]
      remediation_reference_ids = []
      role_definition_ids       = []
      assignment_location       = "westeurope"
      parameters = {
        listOfAllowedLocations = ["westeurope", "northeurope"]
      }
      metadata = {
        controlIds = ["AZ-LZ-001"]
        owner      = "platform-team"
        stage      = "enforced"
      }
    }

    # C. Sandboxes: same control, materially different rollout posture -
    #    enforcement disabled so experiments are not blocked.
    sandboxes = {
      initiative_key            = "sandboxes_baseline"
      scope                     = var.sandboxes_management_group_id
      assignment_name           = "sandboxes-baseline"
      enforcement               = false # DoNotEnforce: observe-first, still governed
      effect                    = "Deny"
      remediate                 = false
      remediate_effects         = ["DeployIfNotExists", "Modify"]
      remediation_reference_ids = []
      role_definition_ids       = []
      assignment_location       = "westeurope"
      parameters = {
        listOfAllowedLocations = ["westeurope", "northeurope"]
      }
      metadata = {
        controlIds = ["AZ-SBX-001"]
        owner      = "platform-team"
        stage      = "observe"
      }
    }
  }

  exemptions = {
    # D. Governed exemption: a time-boxed, owned waiver for ONE workload
    #    subscription against the parent Landing zones assignment. Prefer this
    #    over permanently carving the subscription out with not_scopes: the
    #    exemption expires, carries an owner/tracking reference, and shows up
    #    in governance reporting.
    lz_subscription_waiver = {
      assignment_key       = "landing_zones"
      scope                = var.landing_zone_subscription_id
      name                 = "lz-waiver-data-residency-migration"
      display_name         = "Waiver: data residency migration in progress"
      description          = "Temporary waiver while this workload migrates its data plane out of a non-allowed region. Tracked by ARCH-1234; re-evaluated at expiry."
      category             = "Waiver"
      expires_on           = "2099-12-31" # update when promoting this example
      policy_reference_ids = []           # empty = exempt the whole assignment
      governed = {
        owner              = "workload-team"
        tracking_reference = "ARCH-1234"
        reason             = "Legacy region still required during phased data migration"
        requester          = "workload-team"
        approver           = "platform-team"
        mitigation         = "Compensating network controls; monthly compliance review"
      }
    }
  }
}
