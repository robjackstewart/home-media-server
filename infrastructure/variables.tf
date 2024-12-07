variable "cloudflare_application_name" {
  type = string
  description = "The name of the cloudflare zero trust access application."
  default = "home-media-server"
}

variable "cloudflare_domain" {
  type = string
  description = "The domain in cloudflare under which your home media server will be accessed."
}

variable "cloudflare_tunnel_name" {
  type = string
  description = "The name of the cloudflare tunnel via which your home media server will be accessed."
  default = "home-media-server"
}

variable "cloudflare_tunnel_credential_secret_name" {
  type = string
  description = "The name of the kubernetes secrets in which the cloudflare tunnel credentials will be stored."
  default = "cloudflare-tunnel-credentials"
}

variable "app_registration_client_id" {
  type = string
  description = "The client ID of the app registration which will be used for authentication by the cloudflare application."
}

variable "azure_subscription_id" {
  type = string
  description = "The ID of the subscription in which all azure resources exist."
}

variable "azure_resource_group_name" {
  type = string
  description = "The name of the Azure resource group in which security resources will be created."
  default = "home-media-server-rg"
}

variable "azure_resource_group_location" {
  type = string
  description = "The location of the Azure resource group in which security resources will be created."
  default = "uksouth"
}

variable "azure_key_vault_name" {
  type = string
  description = "The name of the key vault in which secrets will be stored."
  default = "home-media-server-kv"
}

variable "azure_common_keyvault_name" {
  type = string
  description = "The name of the key vault from which secrets will be pulled at infrastructure deployment time."
}

variable "azure_common_keyvault_resource_group" {
  type = string
  description = "The name of the resource group which contains the key vault from which secrets will be pulled at infrastructure deployment time."
}

variable "azure_common_keyvault_client_secret_secret_name" {
  type = string
  description = "The name of the secret in the common keyvault in which the app registration client secret is stored."
}

variable "azure_common_keyvault_vpn_username_secret_name" {
  type = string
  description = "The name of the secret in the common keyvault in which the vpn username is stored."
}

variable "azure_common_keyvault_vpn_password_secret_name" {
  type = string
  description = "The name of the secret in the common keyvault in which the vpn password is stored."
}

variable "azure_common_keyvault_cloudflare_api_token_secret_name" {
  type = string
  description = "The name of the secret in the common keyvaukt the value of which is the API token for your Cloudflare account. Needs to have the following account level grants: Cloudflare Tunnel:Edit, Access: Organizations, Identity Providers, and Groups:Edit, Access: Apps and Policies:Edit, and DNS:Edit for the domain on which your media server will be accessed."
}

variable "azure_common_keyvault_cloudflare_zone_id_secret_name" {
  type = string
  description = "he name of the secret in the common keyvaukt the value of which is the zone ID for the domain through which you will access your home media server"
}

variable "azure_common_keyvault_cloudflare_account_id_secret_name" {
  type = string
  description = "he name of the secret in the common keyvaukt the value of which is the account ID for the domain through which you will access your home media server"
}

variable "timezone" {
  type = string
  description = "Your linux timezone value."
  default = "Europe/London"
}

variable "transmission_web_ui" {
  type = string
  description = "The web UI theme you want for transmission."
  default = "flood-for-transmission"
}

variable "transmission_vpn_type" {
  type = string
  description = "The type of VPN e.g. openvpn or wireguard"
  validation {
    condition     = var.transmission_vpn_type == "openvpn" || var.transmission_vpn_type == "wireguard"
    error_message = "transmission_vpn_type must be 'openvpn' or 'wireguard'"
  }
}

variable "transmission_vpn_provider_name" {
  type = string
  description = "The transmission VPN provider."
}

variable "transmission_vpn_provider_environment_variables" {
  type = list(object({
    name    = string
    value   = string
  }))
  description = "Transmission VPN provicer specific environment variables for Gluetun."
}

variable "transmission_vpn_secret_name" {
  type = string
  description = "The name of the kubernetes secret in which the transmissiong VPN credentials will be stored"
  default = "vpn-credentials"
}

variable "host_storage_config_dir" {
  type = string
  description = "The path on your host to the directory in which all per-app configuration will be saved."
}

variable "host_storage_config_capacity" {
  type = string
  description = "The capacity of the directory in which all per-app configuration will be saved."

}

variable "host_storage_media_dir" {
  type = string
  description = "The path on your host to the directory under which all media will be saved."
}

variable "host_storage_media_capacity" {
  type = string
  description = "The capacity of the directory in which all media will be saved."
}

variable "kubernetes_context" {
  type = string
  default = "k3d-home-media-server"
}

variable "kubernetes_namespace" {
  type = string
  default = "home-media-server"
}

variable "puid" {
  type = string
  default = "1000"
}

variable "guid" {
  type = string
  default = "1000"
}

variable "home_assistant_subdomain" {
  type = string
  default = "home-assistant"
}