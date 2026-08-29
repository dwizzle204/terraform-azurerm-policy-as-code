terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.35, < 6.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47, < 4.0"
    }
  }
}
