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

variable "cloudflare_team_name" {
  type = string
}

variable "unencoded_cloudflare_tunnet_secret" {
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
