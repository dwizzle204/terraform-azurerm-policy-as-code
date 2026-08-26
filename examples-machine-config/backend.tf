terraform {
  # consumers should pin deliberately - see COMPATIBILITY.md
  required_version = ">= 1.8"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.2"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}
