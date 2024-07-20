provider "cloudflare" {
  api_token = data.azurerm_key_vault_secret.cloudflare_api_token.value
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kubernetes_context
}

resource "cloudflare_access_application" "home_media_server" {
  zone_id                   = data.azurerm_key_vault_secret.cloudflare_zone_id.value
  name                      = var.cloudflare_application_name
  domain                    = format("%s.%s", var.cloudflare_application_name, var.cloudflare_domain)
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = true
  allowed_idps              = [cloudflare_access_identity_provider.azure_ad_oauth.id]
}

resource "random_id" "argo_secret" {
  byte_length = 35
}

resource "cloudflare_tunnel" "tunnel" {
  account_id = data.azurerm_key_vault_secret.cloudflare_account_id.value
  name       = var.cloudflare_tunnel_name
  secret     = random_id.argo_secret.b64_std
  config_src = "local"

  depends_on = [
    cloudflare_access_application.home_media_server
  ]
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "security" {
  name     = var.azure_resource_group_name
  location = var.azure_resource_group_location
}

resource "azurerm_key_vault" "keyvault" {
  name                        = var.azure_key_vault_name
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

data "azurerm_key_vault" "common" {
  name                = var.azure_common_keyvault_name
  resource_group_name = var.azure_common_keyvault_resource_group
}

data "azurerm_key_vault_secret" "common_kv_client_secret" {
  name         = var.azure_common_keyvault_client_secret_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

data "azurerm_key_vault_secret" "common_kv_openvpn_username" {
  name         = var.azure_common_keyvault_openvpn_username_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

data "azurerm_key_vault_secret" "common_kv_openvpn_password" {
  name         = var.azure_common_keyvault_openvpn_password_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

data "azurerm_key_vault_secret" "cloudflare_api_token" {
  name         = var.azure_common_keyvault_cloudflare_api_token_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

data "azurerm_key_vault_secret" "cloudflare_zone_id" {
  name         = var.azure_common_keyvault_cloudflare_zone_id_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

data "azurerm_key_vault_secret" "cloudflare_account_id" {
  name         = var.azure_common_keyvault_cloudflare_account_id_secret_name
  key_vault_id = data.azurerm_key_vault.common.id
}

resource "azurerm_key_vault_secret" "client_secret" {
  name         = "client-secret"
  value        = data.azurerm_key_vault_secret.common_kv_client_secret.value
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "azurerm_key_vault_secret" "openvpn_username" {
  name         = "vpn-username"
  value        = data.azurerm_key_vault_secret.common_kv_openvpn_username.value
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "azurerm_key_vault_secret" "openvpn_password" {
  name         = "vpn-password"
  value        = data.azurerm_key_vault_secret.common_kv_openvpn_password.value
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "cloudflare_record" "home_media_server_cname" {
  zone_id = data.azurerm_key_vault_secret.cloudflare_zone_id.value
  name    = var.cloudflare_application_name
  value   = cloudflare_tunnel.tunnel.cname
  type    = "CNAME"
  proxied = true
}

resource "cloudflare_record" "home_assistant_cname" {
  zone_id = data.azurerm_key_vault_secret.cloudflare_zone_id.value
  name    = var.home_assistant_subdomain
  value   = cloudflare_tunnel.tunnel.cname
  type    = "CNAME"
  proxied = true
}


resource "azurerm_key_vault_secret" "tunnel_credentials" {
  name         = "tunnel-credentials"
  value        = jsonencode({"AccountTag"=data.azurerm_key_vault_secret.cloudflare_account_id.value, "TunnelID"=cloudflare_tunnel.tunnel.id, "TunnelSecret"=random_id.argo_secret.b64_std})
  key_vault_id = azurerm_key_vault.keyvault.id
}


resource "cloudflare_access_identity_provider" "azure_ad_oauth" {
  account_id = data.azurerm_key_vault_secret.cloudflare_account_id.value
  name       = "Azure Active Directory via Home Media Server App Registration"
  type       = "azureAD"
  config {
    client_id     = var.app_registration_client_id
    client_secret = azurerm_key_vault_secret.client_secret.value
    directory_id  = data.azurerm_client_config.current.tenant_id
  }
}

resource "kubernetes_namespace" "home-media-server" {
  metadata {
    name = var.kubernetes_namespace
  }
}

resource "kubernetes_secret" "argo_tunnel_credentials" {
  metadata {
    name = var.cloudflare_tunnel_credential_secret_name
    namespace = var.kubernetes_namespace
  }

  data = {
    "credentials.json" = jsonencode({"AccountTag"=data.azurerm_key_vault_secret.cloudflare_account_id.value, "TunnelID"=cloudflare_tunnel.tunnel.id, "TunnelSecret"=random_id.argo_secret.b64_std})
  }
}

resource "kubernetes_secret" "transmission_openvpn_credentials" {
  metadata {
    name = var.transmission_vpn_secret_name
    namespace = var.kubernetes_namespace
  }

  data = {
    username = azurerm_key_vault_secret.openvpn_username.value
    password = azurerm_key_vault_secret.openvpn_password.value
  }

  type = "kubernetes.io/basic-auth"
}

resource "local_file" "values" {
  filename = "../helm/infrastructure.values.yaml"
  content = <<EOT
timezone: ${var.timezone}
PUID: "${var.puid}"
GUID: "${var.guid}"
transmissionopenvpn:
  webui: ${var.transmission_web_ui}
  openvpn:
    provider: ${var.transmission_vpn_provider}
    config: ${var.transmission_vpn_config}
    auth:
      secret:
        name: ${var.transmission_vpn_secret_name}
        keys:
          username: username
          password: password
domain:
  main: ${format("%s.%s", var.cloudflare_application_name, var.cloudflare_domain)}
  homeassistant: ${format("%s.%s", var.home_assistant_subdomain, var.cloudflare_domain)} 
storage:
  host:
    config:
      dir: ${var.host_storage_config_dir}
      capacity: ${var.host_storage_config_capacity}
    media:
      dir: ${var.host_storage_media_dir}
      capacity: ${var.host_storage_media_capacity}
argoTunnel:
  name: ${var.cloudflare_tunnel_name}
  id: ${cloudflare_tunnel.tunnel.id}
  credentials:
    secretName: ${var.cloudflare_tunnel_credential_secret_name}
EOT
}