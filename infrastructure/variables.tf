variable "cloudflare_api_token" {
  type = string
}

variable "cloudflare_zone_id" {
  type = string
}

variable "cloudflare_account_id" {
  type = string
}

variable "cloudflare_application_name" {
  type = string
}

variable "cloudflare_domain" {
  type = string
}

variable "cloudflare_tunnel_name" {
  type = string
}

variable "cloudflare_tunnel_credential_secret_name" {
  type = string
}

variable "cloudflare_team_name" {
  type = string
}

variable "app_registration_client_id" {
  type = string
}

variable "azure_security_resource_group_name" {
    type = string
}

variable "azure_security_resource_group_location" {
    type = string
}

variable "azure_security_key_vault_name" {
    type = string
}

variable "azure_application_registration_name" {
    type = string
}

variable "azure_application_registration_rotation_day_count" {
    type = number
}

variable "timezone" {
  type = string
}

variable "transmission_web_ui" {
  type = string
}

variable "transmission_vpn_provider" {
  type = string
}

variable "transmission_vpn_config" {
  type = string
}

variable "transmission_vpn_secret_name" {
  type = string
}

variable "transmission_vpn_username" {
  type = string
}

variable "transmission_vpn_password" {
  type = string
}

variable "host_storage_config_dir" {
  type = string
}

variable "host_storage_config_capacity" {
  type = string
}

variable "host_storage_media_dir" {
  type = string
}

variable "host_storage_media_capacity" {
  type = string
}

variable "kubernetes_context" {
  type = string
}

variable "kubernetes_namespace" {
  type = string
}

variable "helm_release_name" {
  type = string
}

variable "puid" {
  type = string
}

variable "guid" {
  type = string
}