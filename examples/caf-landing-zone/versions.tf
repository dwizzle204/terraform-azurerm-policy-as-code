terraform {
  # consumers should pin deliberately - see COMPATIBILITY.md
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
  # no backend: this is a reference example. Wire your own remote state
  # following docs/REMOTE_STATE.md before using it for real.
}

provider "azurerm" {
  features {}
}
