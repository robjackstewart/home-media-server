cloudflare_domain="robjackstewart.com"
azure_subscription_id="5148aaa5-6d59-4c4c-bbc9-ad55f535a0c7"
app_registration_client_id="9c0c16ff-1062-4450-9a81-e34b0188d13d"
azure_common_keyvault_name="robstewart-terraform-kv"
azure_common_keyvault_resource_group="tfstate"
azure_common_keyvault_client_secret_secret_name="home-media-server-client-secret"
azure_common_keyvault_vpn_wireguard_private_key_secret_name="vpn-wireguard-private-key"
azure_common_keyvault_cloudflare_api_token_secret_name="home-media-server-cloudflare-api-token"
azure_common_keyvault_cloudflare_zone_id_secret_name="home-media-server-cloudflare-zone-id"
azure_common_keyvault_cloudflare_account_id_secret_name="home-media-server-cloudflare-account-id"
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
host_storage_config_dir="/home-media-server/config"
host_storage_config_capacity="5Gi"
host_storage_media_dir="/home-media-server/media"
host_storage_media_capacity="500Gi"
entra_id_access_group_object_id="a0f74747-ec30-4632-b9d5-fc9e0b39d3f9"
local_network_ip_address="192.168.50.109"