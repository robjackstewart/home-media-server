variable "cloudflare_api_token" {
  type = string
  description = "The API token for your Cloudflare account. Needs to have the following account level grants: Cloudflare Tunnel:Edit, Access: Organizations, Identity Providers, and Groups:Edit, Access: Apps and Policies:Edit, and DNS:Edit for the domain on which your media server will be accessed."
}

variable "cloudflare_zone_id" {
  type = string
  description = "The zone ID for the domain through which you will access your home media server"
}

variable "cloudflare_account_id" {
  type = string
  description = "The account ID for the domain through which you will access your home media server"
}

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

variable "azure_security_resource_group_name" {
  type = string
  description = "The name of the Azure resource group in which security resources will be created."
}

variable "azure_security_resource_group_location" {
  type = string
  description = "The location of the Azure resource group in which security resources will be created."
}

variable "azure_security_key_vault_name" {
  type = string
  description = "The name of the key vault in which secrets will be stored."
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

variable "azure_common_keyvault_client_secret_openvpn_username_secret_name" {
  type = string
  description = "The name of the secret in the common keyvault in which the open vpn username is stored."
}

variable "azure_common_keyvault_client_secret_openvpn_password_secret_name" {
  type = string
  description = "The name of the secret in the common keyvault in which the open vpn password is stored."
}

variable "timezone" {
  type = string
  description = "Your linux timezone value."
}

variable "transmission_web_ui" {
  type = string
  description = "The web UI theme you want for transmission."
  default = "flood-for-transmission"
}

variable "transmission_vpn_provider" {
  type = string
  description = "The transmission open VPN provider."
}

variable "transmission_vpn_config" {
  type = string
  description = "The transmission open VPN config."
}

variable "transmission_vpn_secret_name" {
  type = string
  description = "The name of the kubernetes secret in which the transmissiong open VPN credentials will be stored"
  default = "transmission-openvpn-credentials"
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