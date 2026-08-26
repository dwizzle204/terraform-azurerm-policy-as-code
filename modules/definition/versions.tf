terraform {
  required_version = ">= 1.4"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.12"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }
}
