provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  subscription_id = var.azure_subscription_id
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kubernetes_context
}

provider "tailscale" {
  oauth_client_id     = data.azurerm_key_vault_secret.tailscale_terraform_oauth_client_id.value
  oauth_client_secret = data.azurerm_key_vault_secret.tailscale_terraform_oauth_client_secret.value
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "home_media_server" {
  name     = var.azure_resource_group_name
  location = var.azure_resource_group_location
}

resource "azurerm_key_vault" "keyvault" {
  name                        = var.azure_key_vault_name
  location                    = azurerm_resource_group.home_media_server.location
  resource_group_name         = azurerm_resource_group.home_media_server.name
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
      "Recover",
      "Delete"
    ]

    storage_permissions = [
      "Get",
    ]
  }
}

data "azurerm_key_vault" "common" {
  name                = var.azure_common_keyvault_name
  resource_group_name = var.azure_common_keyvault_resource_group
}

data "azurerm_key_vault_secret" "common_kv_vpn_wireguard_private_key" {
  name         = var.azure_common_keyvault_vpn_wireguard_private_key_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

data "azurerm_key_vault_secret" "tailscale_terraform_oauth_client_id" {
  name         = var.azure_common_keyvault_tailscale_terraform_oauth_client_id_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

data "azurerm_key_vault_secret" "tailscale_terraform_oauth_client_secret" {
  name         = var.azure_common_keyvault_tailscale_terraform_oauth_client_secret_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

data "azurerm_key_vault_secret" "tailscale_operator_oauth_client_id" {
  name         = var.azure_common_keyvault_tailscale_operator_oauth_client_id_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

data "azurerm_key_vault_secret" "tailscale_operator_oauth_client_secret" {
  name         = var.azure_common_keyvault_tailscale_operator_oauth_client_secret_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

resource "azurerm_key_vault_secret" "vpn_wireguard_private_key" {
  name         = "vpn-wireguard-private-key"
  value        = data.azurerm_key_vault_secret.common_kv_vpn_wireguard_private_key.value
  key_vault_id = azurerm_key_vault.keyvault.id
}

# Replaces the Cloudflare Access application + Entra ID group as the authorization boundary:
# only devices signed into this tailnet can reach tag:k8s. Note this resource replaces the
# entire tailnet policy file - if the tailnet already has hand-written rules, fold them in here
# before the first apply.
resource "tailscale_acl" "policy" {
  acl = jsonencode({
    tagOwners = {
      "tag:k8s-operator" = []
      "tag:k8s"          = ["tag:k8s-operator"]
    }
    # ProxyGroup-backed Ingress advertises Tailscale Services; without this the proxies come up
    # healthy but the Services stay unapproved and the MagicDNS names never resolve.
    autoApprovers = {
      services = {
        "tag:k8s" = ["tag:k8s"]
      }
    }
    grants = [{
      src = ["autogroup:member"]
      dst = ["tag:k8s"]
      ip  = ["*"]
    }]
  })
}

resource "kubernetes_namespace_v1" "home-media-server" {
  metadata {
    name = var.kubernetes_namespace
  }
}

resource "kubernetes_secret_v1" "tailscale_operator_oauth" {
  metadata {
    name      = var.tailscale_operator_oauth_secret_name
    namespace = kubernetes_namespace_v1.home-media-server.metadata[0].name
  }

  data = {
    client_id     = data.azurerm_key_vault_secret.tailscale_operator_oauth_client_id.value
    client_secret = data.azurerm_key_vault_secret.tailscale_operator_oauth_client_secret.value
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "vpn_credentials" {
  metadata {
    name = var.transmission_vpn_secret_name
    namespace = kubernetes_namespace_v1.home-media-server.metadata[0].name
  }

  data = {
    wireguard_private_key = azurerm_key_vault_secret.vpn_wireguard_private_key.value
  }

  type = "Opaque"
}

resource "local_file" "values" {
  filename = "../helm/infrastructure.values.yaml"
  content = yamlencode({
    # These key names must match what the Helm templates read. They previously emitted
    # `timezone` and `GUID` while every template read `.Values.Timezone` and `.Values.PGID`,
    # so TZ and PGID silently rendered as empty strings across the chart (20 env vars,
    # verified with `helm template` before and after).
    Timezone = var.timezone
    PUID     = var.puid
    PGID     = var.guid
    transmission = {
      webui = var.transmission_web_ui
    }
    vpn = {
      provider = {
        name = var.transmission_vpn_provider_name
        env = var.transmission_vpn_provider_environment_variables
      }
      auth = {
        secret = {
          name = var.transmission_vpn_secret_name
          keys = {
            wireguard_private_key = "wireguard_private_key"
          }
        }
      }
    }
    domain = {
      zone = var.cloudflare_domain
      main = format("%s.%s", var.cloudflare_application_name, var.cloudflare_domain)
    }
    tailnet = var.tailscale_tailnet_name
    storage = {
      host = {
        config = {
          dir      = var.host_storage_config_dir
          capacity = var.host_storage_config_capacity
        }
        media = {
          dir      = var.host_storage_media_dir
          capacity = var.host_storage_media_capacity
        }
      }
    }
  })
}