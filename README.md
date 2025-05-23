# Home Media Server

## Requirements
1. A cloudflare account and domain
1. An azure account and subscription
1. A host with an NVIDIA GPU

## Getting Started
1. Install the [Task CLI](https://taskfile.dev/installation/)
1. Install the [NVIDIA Container Runtime](https://developer.nvidia.com/container-runtime) in the environment in which you will run the K3d cluster containers.
1. Check that you have the necessary dependencies. This will error if you are missing any required tooling.

    ``` shell
    task check-dependencies
    ```

1. Create [`config/variables.tfvars`](config/variables.tfvars) and populate it with appropriate values. Here is an example of its contents:

    ```
    cloudflare_domain="mydomain.com"
    app_registration_client_id="<your-app-registration-client-id>"
    azure_common_keyvault_name="terraform-kv"
    azure_common_keyvault_resource_group="tfstate"
    azure_common_keyvault_client_secret_secret_name="home-media-server-client-secret"
    azure_common_keyvault_client_secret_secret_name="vpn-private-key-secret"
    azure_common_keyvault_cloudflare_api_token_secret_name="home-media-server-cloudflare-api-token"
    azure_common_keyvault_cloudflare_zone_id_secret_name="home-media-server-cloudflare-zone-id"
    azure_common_keyvault_cloudflare_account_id_secret_name="home-media-server-cloudflare-account-id"
    timezone="Europe/London"
    transmission_vpn_provider_name="mullvad"
    transmission_vpn_provider_environment_variables=[]
    host_storage_config_dir="/home-media-server/config"
    host_storage_config_capacity="5Gi"
    host_storage_media_dir="/home-media-server/media"
    host_storage_media_capacity="500Gi"
    ```

    See `infrastructure/variables.tf` for all variables and descriptions.
1. Now run a full deployment

    ``` shell
    task recreate
    ```
1. Configure the individual apps via their UI.

## WSL2
If you are running the K3d cluster and docker in WSL2, then you will need to forward the ports on your windows host into the WSL2 ports.

1. Give your WSL2 instance a static IP
    1. Get your WSL2 IP address `hostname -I` and take the first IP address if there are multiple. You can check its right by running `ip addr show eth0` and taking the `inet` value.
    1. Get your current gateway by running `ip route`. It follows `default via`.
    1. Edit the networm interfaces config: `sudo nano /etc/network/interfaces` adding the following content:
        ``` bash
        auto eth0
        iface eth0 inet static
            address <your-static-ip>
            netmask 255.255.255.0
            gateway <your-gateway-ip>
        ```
    1. On your windows host, run `wsl --shutdown`.
    1. Open a new WSL2 tab to restart WSL.
1. Forward ports on your windows host to your WSL2 instance but opening powershell on your windows host and running [this script](./scripts/expose-jellyfin-on-wsl2.ps1) in powershell as Administrator.
