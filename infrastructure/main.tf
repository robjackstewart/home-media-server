provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

resource "cloudflare_tunnel" "example" {
  account_id = var.cloudflare_account_id
  name       = var.cloudflare_tunnel_name
  secret     = base64encode(var.unencoded_cloudflare_tunnet_secret)
}

resource "cloudflare_access_application" "staging_app" {
  zone_id                   = var.cloudflare_zone_id
  name                      = var.cloudflare_application_name
  domain                    = var.cloudflare_domain
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = false
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "security" {
  name     = var.azure_security_resource_group_name
  location = var.azure_security_resource_group_location
}

resource "azurerm_key_vault" "keyvault" {
  name                        = var.azure_security_key_vault_name
  location                    = azurerm_resource_group.security.location
  resource_group_name         = azurerm_resource_group.security.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get",
    ]

    secret_permissions = [
      "Get",
      "Set",
      "List",
      "Recover"
    ]

    storage_permissions = [
      "Get",
    ]
  }
}

resource "azuread_application" "app_registration" {
  display_name = var.azure_application_registration_name
}

resource "time_rotating" "app_registration" {
  rotation_days = var.azure_application_registration_rotation_day_count
}

resource "azuread_application_password" "example" {
  application_object_id = azuread_application.app_registration.object_id
  rotate_when_changed = {
    rotation = time_rotating.app_registration.id
  }
}

resource "random_password" "client_secret" {
  length           = 32
  special          = true
  override_special = "_@%"
}

resource "azurerm_key_vault_secret" "client_secret" {
  name         = "client-secret"
  value        = random_password.client_secret.result
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "cloudflare_access_identity_provider" "azure_ad_oauth" {
  account_id = var.cloudflare_account_id
  name       = var.azure_application_registration_name
  type       = "azureAD"
  config {
    client_id     = azuread_application.app_registration.object_id
    client_secret = azurerm_key_vault_secret.client_secret.value
    directory_id  = data.azurerm_client_config.current.tenant_id
  }
}