provider "cloudflare" {
  api_token = var.cloudflare_api_token
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