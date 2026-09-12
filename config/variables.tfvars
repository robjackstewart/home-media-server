azure_subscription_id="5148aaa5-6d59-4c4c-bbc9-ad55f535a0c7"
azure_common_keyvault_name="robstewart-terraform-kv"
azure_common_keyvault_resource_group="tfstate"
azure_common_keyvault_vpn_wireguard_private_key_secret_name="vpn-wireguard-private-key"
# The bare token (no "Bearer " prefix - Terraform adds that) from Hardcover.app -> Settings ->
# Hardcover API, stored under this name in the common Key Vault. Used by rreading-glasses
# (Bookshelf's self-hosted metadata backend). Expires annually on 1 January - renew by hand in
# Hardcover's own console when it does.
azure_common_keyvault_hardcover_api_token_secret_name="home-media-server-hardcover-api-token"
# The bare ComicVine API key (free, from https://comicvine.gamespot.com/api/) Mylar3 needs to
# search for comics, stored under this name in the common Key Vault.
azure_common_keyvault_comicvine_api_key_secret_name="home-media-server-comicvine-api-key"
# Fill these in with the names you gave the two secrets in the common Key Vault after creating
# the bootstrap Tailscale OAuth client (see README.md's "Remote access" section for the required
# scopes). Terraform creates the Kubernetes operator's own OAuth client itself now.
azure_common_keyvault_tailscale_terraform_oauth_client_id_secret_name="home-media-server-tailscale-terraform-oauth-client-id"
azure_common_keyvault_tailscale_terraform_oauth_client_secret_secret_name="home-media-server-tailscale-terraform-oauth-client-secret"
# Replace with your own tailnet's MagicDNS suffix, from the admin console's DNS page.
tailscale_tailnet_name="tail17a6b2.ts.net"
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