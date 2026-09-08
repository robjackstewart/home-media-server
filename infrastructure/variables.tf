variable "azure_subscription_id" {
  type = string
  description = "The ID of the subscription in which all azure resources exist."
}

variable "azure_resource_group_name" {
  type = string
  description = "The name of the Azure resource group in which home media server resources will be created."
  default = "home-media-server-rg"
}

variable "azure_resource_group_location" {
  type = string
  description = "The location of the Azure resource group in which home media server resources will be created."
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

variable "azure_common_keyvault_vpn_wireguard_private_key_secret_name" {
  type = string
  description = "The name of the secret in the common keyvault in which the vpn wireguard private key is stored."
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
  # Native k3s writes a context named "default" into /etc/rancher/k3s/k3s.yaml.
  # k3d used to name it "k3d-<cluster-name>".
  default = "default"
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

variable "azure_common_keyvault_tailscale_terraform_oauth_client_id_secret_name" {
  type        = string
  description = "The name of the secret in the common keyvault holding the client ID of the bootstrap Tailscale OAuth client Terraform authenticates as. Needs write scope on: policy file (the tailnet ACL), dns (MagicDNS), feature_settings (HTTPS certificates), and oauth_keys (creating the Kubernetes operator's own OAuth client)."
}

variable "azure_common_keyvault_tailscale_terraform_oauth_client_secret_secret_name" {
  type        = string
  description = "The name of the secret in the common keyvault holding the client secret of the bootstrap Tailscale OAuth client Terraform authenticates as."
}

variable "tailscale_tailnet_name" {
  type        = string
  description = "The tailnet's MagicDNS suffix (e.g. 'tailxxxx.ts.net'), used to build each app's https://<subdomain>.<tailnet> address."
}

variable "tailscale_operator_oauth_secret_name" {
  type        = string
  description = "The name of the kubernetes secret in which the Tailscale operator's OAuth credentials will be stored. Must be 'operator-oauth' - this name and its client_id/client_secret keys are hardcoded by the tailscale-operator Helm chart."
  default     = "operator-oauth"
}
