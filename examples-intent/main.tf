# Data-driven example: declare policy intent in YAML, decode at the root.
#
# assignments.yaml:
#   platform:
#     initiative_key: platform_baseline
#     scope: /providers/Microsoft.Management/managementGroups/platform
#     effect: Deny
#
# terraform init -backend=false && terraform validate

terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.2"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  assignment_intents = try(yamldecode(file("${path.module}/assignments.yaml")), {})
}

module "policy_intent" {
  source = "..//modules/intent"

  definitions = {
    member_a = { category = "Monitoring", policy_name = "deploy_vnet_diagnostic_setting" }
  }

  initiatives = {
    platform_baseline = {
      display_name           = "Platform Baseline"
      management_group_id    = "/providers/Microsoft.Management/managementGroups/platform"
      member_definition_keys = ["member_a"]
    }
  }

  assignments = local.assignment_intents
}
