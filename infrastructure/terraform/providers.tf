provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  use_oidc        = true
  features {}
}

provider "azuread" {
  tenant_id = var.tenant_id
  use_oidc  = true
}

variable "tenant_id" {
  type        = string
  description = "Confirmed Microsoft Entra tenant ID."
}

variable "subscription_id" {
  type        = string
  description = "Confirmed Azure subscription ID."
}

data "azurerm_client_config" "current" {}

check "confirmed_identity" {
  assert {
    condition     = data.azurerm_client_config.current.tenant_id == var.tenant_id && data.azurerm_client_config.current.subscription_id == var.subscription_id
    error_message = "OIDC identity is not operating in the configured tenant and subscription."
  }
}

