terraform {
  required_version = "= 1.16.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 3.10.0"
    }
  }

  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true
  }
}

