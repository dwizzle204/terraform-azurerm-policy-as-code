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
