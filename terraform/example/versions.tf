terraform {
  required_version = "~>1.0.0"
  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.2.0"
    }
  }
}