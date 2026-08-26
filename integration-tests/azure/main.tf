# LIVE Azure integration configuration — requires real credentials.
# NOT run in normal PR validation. See README.md in this directory.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.12"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "test_subscription_id" {
  type        = string
  description = "Disposable Azure subscription used for live testing only"
}

module "definition_live" {
  source          = "../../modules/definition"
  policy_category = "Monitoring"
  policy_name     = "deploy_vnet_diagnostic_setting"
}

module "assignment_live" {
  source            = "../../modules/def_assignment"
  assignment_scope  = "/subscriptions/${var.test_subscription_id}"
  definition        = module.definition_live.definition
  assignment_effect = "Audit"
  skip_remediation  = true
}
