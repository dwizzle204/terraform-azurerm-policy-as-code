terraform {
  required_version = ">= 1.8" # floor: offline terraform test/mock_provider suites; oldest maintained line validated by CI
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.35, < 6.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.0, < 4.0"
    }
  }
}
