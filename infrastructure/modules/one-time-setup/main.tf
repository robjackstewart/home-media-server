provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "example" {
  name     = var.azure_security_resource_group_name
  location = var.azure_security_resource_group_location
}

resource "azurerm_key_vault" "example" {
  name                        = var.azure_security_key_vault_name
  location                    = azurerm_resource_group.example.location
  resource_group_name         = azurerm_resource_group.example.name
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

