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
  domain                    = var.cloudflare_domain
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

resource "azuread_application" "app_registration" {
  display_name = var.azure_application_registration_name
  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id    = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0" # email
      type  = "Scope"
    }

    resource_access {
      id    = "7427e0e9-2fba-42fe-b0c0-848c9e6a8182" # offline_access
      type  = "Scope"
    }
    
    resource_access {
      id    = "37f7f235-527c-4136-accd-4a02d197296e" # openid
      type  = "Scope"
    }

    resource_access {
      id    = "14dad69e-099b-42c9-810b-d002981feec1" # profile
      type  = "Scope"
    }

    resource_access {
      id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" # User.Read
      type = "Role"
    }

    resource_access {
      id    = "06da0dbc-49e2-44d2-8312-53f166ab848a" # Directory.Read.All
      type  = "Scope"
    }

    resource_access {
      id    = "bc024368-1153-4739-b217-4326f2e966d0" # GroupMember.Read.All
      type  = "Scope"
    }
  }
  web {
    redirect_uris = ["https://${var.cloudflare_team_name}.cloudflareaccess.com/cdn-cgi/access/callback"]
  }
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
  name       = var.azure_application_registration_name
  type       = "azureAD"
  config {
    client_id     = azuread_application.app_registration.application_id
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

resource "helm_release" "home-media-server" {
  name  = var.helm_release_name
  chart = "../k8s/helm"
  namespace = var.kubernetes_namespace
  timeout = 10000

  depends_on = [
    cloudflare_tunnel.example, # wait for tunnel to exist
    kubernetes_secret.argo_tunnel_credentials,
    kubernetes_secret.transmission_openvpn_credentials,
    cloudflare_record.tunnel_cname
  ]

  set {
    name  = "timezone"
    value = var.timezone
  }

  set {
    name  = "puid"
    value = var.puid
  }

  set {
    name  = "guid"
    value = var.guid
  }

  set {
    name  = "transmissionopenvpn.webui"
    value = var.transmission_web_ui
  }

  set {
    name  = "transmissionopenvpn.openvpn.provider"
    value = var.transmission_vpn_provider
  }

  set {
    name  = "transmissionopenvpn.openvpn.config"
    value = var.transmission_vpn_config
  }

  set {
    name  = "transmissionopenvpn.openvpn.auth.secret.name"
    value = var.transmission_vpn_secret_name
  }

  set {
    name  = "transmissionopenvpn.openvpn.auth.secret.keys.username"
    value = "username"
  }

  set {
    name  = "transmissionopenvpn.openvpn.auth.secret.keys.password"
    value = "password"
  }

  set {
    name  = "storage.host.config.dir"
    value = var.host_storage_config_dir
  }

  set {
    name  = "storage.host.config.capacity"
    value = var.host_storage_config_capacity
  }

  set {
    name  = "storage.host.media.dir"
    value = var.host_storage_media_dir
  }

  set {
    name  = "storage.host.media.capacity"
    value = var.host_storage_media_capacity
  }

  set {
    name  = "domain"
    value = format("%s.%s", var.cloudflare_application_name, var.cloudflare_domain)
  }

  set {
    name  = "argoTunnel.name"
    value = var.cloudflare_tunnel_name
  }

  set {
    name  = "argoTunnel.id"
    value = cloudflare_tunnel.example.id
  }

  set {
    name  = "argoTunnel.credentials.secretName"
    value = var.cloudflare_tunnel_credential_secret_name
  }

}