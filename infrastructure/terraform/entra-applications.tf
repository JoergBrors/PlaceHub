data "azuread_client_config" "current" {}

locals {
  approved_web_redirect_uris = [
    "https://localhost:3242/signin-oidc",
    "https://localhost:8443/signin-oidc",
  ]

  microsoft_graph_application_id = "00000003-0000-0000-c000-000000000000"
  approved_read_only_scopes = {
    "Place.Read.All"      = "cb8f45a0-5c2e-4ea1-b803-84b870a7d7ec"
    "Calendars.ReadBasic" = "662d75ba-a364-42ad-adee-f5f880ea4878"
  }

  placehub_user_roles = {
    "PlaceHub.OfficeManager" = {
      id          = "166b3fc4-fb93-401b-b856-bffa0d682447"
      description = "Manage approved PlaceHub office operations within assigned locations."
    }
    "PlaceHub.LocationManager" = {
      id          = "228e1fa0-cca2-4ac4-bc44-987ee444ba4c"
      description = "Manage approved PlaceHub operations for assigned locations."
    }
    "PlaceHub.SystemAdministrator" = {
      id          = "9a3f940c-08c4-4bd7-8cfa-106eaab349a5"
      description = "Administer PlaceHub application configuration without tenant administration."
    }
  }
}

resource "azuread_application" "placehub_web" {
  display_name                   = "placehub-frontend-development"
  sign_in_audience               = "AzureADMyOrg"
  fallback_public_client_enabled = false
  owners                         = [data.azuread_client_config.current.object_id]

  dynamic "app_role" {
    for_each = local.placehub_user_roles
    content {
      allowed_member_types = ["User"]
      description          = app_role.value.description
      display_name         = app_role.key
      enabled              = true
      id                   = app_role.value.id
      value                = app_role.key
    }
  }

  required_resource_access {
    resource_app_id = local.microsoft_graph_application_id

    dynamic "resource_access" {
      for_each = local.approved_read_only_scopes
      content {
        id   = resource_access.value
        type = "Scope"
      }
    }
  }

  web {
    homepage_url  = "https://localhost:3242/"
    logout_url    = "https://localhost:3242/signout-callback-oidc"
    redirect_uris = local.approved_web_redirect_uris

    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = false
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_service_principal" "placehub_web" {
  client_id                    = azuread_application.placehub_web.client_id
  app_role_assignment_required = true
  owners                       = [data.azuread_client_config.current.object_id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_application" "m365_provisioning" {
  display_name                   = "placehub-m365-provisioning-development"
  sign_in_audience               = "AzureADMyOrg"
  fallback_public_client_enabled = false
  owners                         = [data.azuread_client_config.current.object_id]

  lifecycle {
    prevent_destroy = true
  }
}

resource "azuread_service_principal" "m365_provisioning" {
  client_id                    = azuread_application.m365_provisioning.client_id
  app_role_assignment_required = true
  owners                       = [data.azuread_client_config.current.object_id]

  lifecycle {
    prevent_destroy = true
  }
}

