cloudflare_domain="robjackstewart.com"
azure_subscription_id="5148aaa5-6d59-4c4c-bbc9-ad55f535a0c7"
app_registration_client_id="9c0c16ff-1062-4450-9a81-e34b0188d13d"
azure_common_keyvault_name="robstewart-terraform-kv"
azure_common_keyvault_resource_group="tfstate"
azure_common_keyvault_client_secret_secret_name="home-media-server-client-secret"
azure_common_keyvault_vpn_username_secret_name="home-media-server-vpn-username"
azure_common_keyvault_vpn_password_secret_name="home-media-server-vpn-password"
azure_common_keyvault_cloudflare_api_token_secret_name="home-media-server-cloudflare-api-token"
azure_common_keyvault_cloudflare_zone_id_secret_name="home-media-server-cloudflare-zone-id"
azure_common_keyvault_cloudflare_account_id_secret_name="home-media-server-cloudflare-account-id"
transmission_vpn_provider_name="mullvad"
transmission_vpn_type="openvpn"
transmission_vpn_provider_environment_variables=[
    {
        name = "SERVER_COUNTRIES"
        value = "UK"
    },
    {
        name = "OWNED_ONLY"
        value = "yes"
    }
]
host_storage_config_dir="/home-media-server/config"
host_storage_config_capacity="5Gi"
host_storage_media_dir="/home-media-server/media"
host_storage_media_capacity="500Gi"