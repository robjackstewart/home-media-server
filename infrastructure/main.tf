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

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = var.kubernetes_context
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "cloudflare_access_application" "home_media_server" {
  zone_id                   = var.cloudflare_zone_id
  name                      = var.cloudflare_application_name
  domain                    = format("%s.%s", var.cloudflare_application_name, var.cloudflare_domain)
  type                      = "self_hosted"
  session_duration          = "24h"
  auto_redirect_to_identity = false
}

resource "random_id" "argo_secret" {
  byte_length = 35
}

resource "cloudflare_tunnel" "example" {
  account_id = var.cloudflare_account_id
  name       = var.cloudflare_tunnel_name
  secret     = random_id.argo_secret.b64_std
  config_src = "local"

  depends_on = [
    cloudflare_access_application.home_media_server
  ]
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

data "azurerm_key_vault" "terraform" {
  name                = "robstewart-terraform-kv"
  resource_group_name = "tfstate"
}

data "azurerm_key_vault_secret" "terraform_state_client_secret" {
  name         = "home-media-server-client-secret"
  key_vault_id = data.azurerm_key_vault.terraform.id
}

resource "azurerm_key_vault_secret" "client_secret" {
  name         = "client-secret"
  value        = data.azurerm_key_vault_secret.terraform_state_client_secret.value
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "cloudflare_record" "tunnel_cname" {
  zone_id = var.cloudflare_zone_id
  name    = var.cloudflare_application_name
  value   = cloudflare_tunnel.example.cname
  type    = "CNAME"
  proxied = true
}


resource "azurerm_key_vault_secret" "tunnel_credentials" {
  name         = "tunnel-credentials"
  value        = jsonencode({"AccountTag"=var.cloudflare_account_id, "TunnelID"=cloudflare_tunnel.example.id, "TunnelSecret"=random_id.argo_secret.b64_std})
  key_vault_id = azurerm_key_vault.keyvault.id
}


resource "cloudflare_access_identity_provider" "azure_ad_oauth" {
  account_id = var.cloudflare_account_id
  name       = "Azure Active Directory via Home Media Server App Registration"
  type       = "azureAD"
  config {
    client_id     = var.app_registration_client_id
    client_secret = data.azurerm_key_vault_secret.terraform_state_client_secret.value
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
    "credentials.json" = jsonencode({"AccountTag"=var.cloudflare_account_id, "TunnelID"=cloudflare_tunnel.example.id, "TunnelSecret"=random_id.argo_secret.b64_std})
  }
}

resource "kubernetes_secret" "transmission_openvpn_credentials" {
  metadata {
    name = var.transmission_vpn_secret_name
    namespace = var.kubernetes_namespace
  }

  data = {
    username = var.transmission_vpn_username
    password = var.transmission_vpn_password
  }

  type = "kubernetes.io/basic-auth"
}

resource "local_file" "values" {
  filename = "../k8s/helm/values.yasml"
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
storage:
  host:
    config:
      dir: ${var.host_storage_config_dir}
      capacity: ${var.host_storage_config_capacity}
    media:
      dir: ${var.host_storage_media_dir}
      capacity: ${var.host_storage_media_capacity}
    
domain: ${format("%s.%s", var.cloudflare_application_name, var.cloudflare_domain)}
argoTunnel:
  name: ${var.cloudflare_tunnel_name}
  id: ${cloudflare_tunnel.example.id}
  credentials:
    secretName: ${var.cloudflare_tunnel_credential_secret_name}
EOT
}