terraform {
  # consumers should pin deliberately - see COMPATIBILITY.md
  required_version = ">= 1.11"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.2"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.1"
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  features {}
}
