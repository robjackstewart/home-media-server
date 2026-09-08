azure_subscription_id="5148aaa5-6d59-4c4c-bbc9-ad55f535a0c7"
azure_common_keyvault_name="robstewart-terraform-kv"
azure_common_keyvault_resource_group="tfstate"
azure_common_keyvault_vpn_wireguard_private_key_secret_name="vpn-wireguard-private-key"
# Fill these in with the names you gave the four secrets in the common Key Vault after creating
# the two Tailscale OAuth clients (see the migration plan's Prerequisites section).
azure_common_keyvault_tailscale_terraform_oauth_client_id_secret_name="home-media-server-tailscale-terraform-oauth-client-id"
azure_common_keyvault_tailscale_terraform_oauth_client_secret_secret_name="home-media-server-tailscale-terraform-oauth-client-secret"
azure_common_keyvault_tailscale_operator_oauth_client_id_secret_name="home-media-server-tailscale-operator-oauth-client-id"
azure_common_keyvault_tailscale_operator_oauth_client_secret_secret_name="home-media-server-tailscale-operator-oauth-client-secret"
# Replace with your own tailnet's MagicDNS suffix, from the admin console's DNS page.
tailscale_tailnet_name="T3UUSVzTHr11CNTRL.ts.net"
transmission_vpn_provider_name="mullvad"
transmission_vpn_provider_environment_variables=[
    {
        name = "SERVER_COUNTRIES"
        value = "UK"
    },
    {
        name = "OWNED_ONLY"
        value = "yes"
    },
    {
        name = "WIREGUARD_ADDRESSES"
        value = "10.73.48.99/32"
    }
]
host_storage_config_dir="/srv/home-media-server/config"
host_storage_config_capacity="5Gi"
host_storage_media_dir="/srv/home-media-server/media"
host_storage_media_capacity="600Gi"