# LIVE Azure integration configuration — requires real credentials.
# NOT run in normal PR validation. See README.md in this directory.

terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.35, < 6.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.test_subscription_id
}

variable "test_subscription_id" {
  type        = string
  description = "Disposable Azure subscription used for live testing only. Pass with: terraform test -var=test_subscription_id=$ARM_SUBSCRIPTION_ID"
}

# Custom definition creation exercises real ARM / Azure Policy API acceptance.
# Live assignment + remediation coverage requires dependent resources (e.g. a
# Log Analytics workspace) and is intentionally out of scope for this skeleton;
# extend it with disposable fixtures if needed.
module "definition_live" {
  source          = "../../modules/definition"
  policy_category = "Monitoring"
  policy_name     = "deploy_vnet_diagnostic_setting"
}

module "initiative_sub_live" {
  source                  = "../../modules/initiative"
  initiative_name         = "live-sub-initiative"
  initiative_display_name = "Live Subscription Initiative"
  # management_group_id omitted => subscription scope (P1)
  member_definitions = [module.definition_live.definition]
}

# Built-in + assignment/exemption live path (P3 docs)
module "intent_builtin_live" {
  source = "../../modules/intent"

  definitions = {
    builtin_allowed_locations = {
      source        = "builtin"
      definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e765b5de-1225-4ba3-bd56-1ac6695af988"
    }
  }
  initiatives = {
    builtin_test = {
      display_name           = "Built-in Test"
      member_definition_keys = ["builtin_allowed_locations"]
    }
  }
  assignments = {
    builtin_assign = {
      initiative_key = "builtin_test"
      scope          = "/subscriptions/${var.test_subscription_id}"
    }
  }
  exemptions = {
    builtin_waiver = {
      assignment_key = "builtin_assign"
      scope          = "/subscriptions/${var.test_subscription_id}"
      name           = "builtin-waiver-live"
      display_name   = "Built-in Waiver Live"
      description    = "Live test waiver for built-in assignment"
      category       = "Waiver"
      expires_on     = "2030-12-31"
    }
  }
}

# NOTE: deploy_vnet_diagnostic_setting requires parameters without defaultValue
# (workspaceId, storageAccountId, eventHubAuthorizationRuleId, eventHubName).
# This live assignment is intentionally commented out until disposable
# fixtures exist — enabling it without parameters fails at apply (Codex P2 on PR #52).
# module "assignment_live" {
#   source           = "../../modules/def_assignment"
#   assignment_scope = "/subscriptions/${var.test_subscription_id}"
#   definition       = module.definition_live.definition
# }
