# Home Media Server

A Jellyfin-centred media stack running on **native k3s** on bare-metal Linux, with the NVIDIA
GPU attached directly for hardware transcoding, exposed to the LAN via k3s's built-in ServiceLB
and to the internet through a Cloudflare Tunnel behind Entra ID authentication.

## Requirements

1. A Cloudflare account and domain
1. An Azure account and subscription
1. A Linux host with an NVIDIA GPU (Ubuntu 24.04 LTS or similar)

Note this runs **directly on the host**, not inside Docker or WSL2. Docker is not required.

## Host setup

Order matters: install the container toolkit **before** k3s, because k3s only probes for
`nvidia-container-runtime` when it starts.

1. **NVIDIA driver and device nodes**

    ``` shell
    sudo ubuntu-drivers install
    sudo systemctl enable --now nvidia-persistenced
    nvidia-smi          # must list the GPU
    ls /dev/nvidia*     # nvidia0, nvidiactl, nvidia-uvm must exist
    ```

1. **NVIDIA Container Toolkit** — see
   [NVIDIA's installation guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

1. **Host storage** — these paths are bound into the cluster as hostPath PersistentVolumes,
   and must be owned by the UID/GID the containers run as (`puid`/`guid`, default `1000`):

    ``` shell
    sudo mkdir -p /srv/home-media-server/{config,media}
    sudo chown -R 1000:1000 /srv/home-media-server
    ```

1. **k3s** — installed with the declarative config in [`k3s/config.yaml`](k3s/config.yaml),
   which disables Traefik (ingress is nginx-gateway-fabric) and labels the node as GPU-capable:

    ``` shell
    task k3s:cluster:install
    task k3s:use-kube-context
    ```

1. **Confirm k3s found the GPU runtime.** k3s writes the nvidia runtime into containerd's
   config itself once it detects the host toolkit — there is no custom node image to build:

    ``` shell
    task k3s:gpu:check
    ```

## Getting started

1. Install the [Task CLI](https://taskfile.dev/installation/), plus `helm`, `kubectl`,
   `terraform`, `az` and `yq`.
1. Check the environment. This errors if any tooling, the k3s service, or the GPU is missing:

    ``` shell
    task environment:check
    ```

1. Create [`config/variables.tfvars`](config/variables.tfvars) and populate it. For example:

    ```
    cloudflare_domain="mydomain.com"
    app_registration_client_id="<your-app-registration-client-id>"
    azure_common_keyvault_name="terraform-kv"
    azure_common_keyvault_resource_group="tfstate"
    azure_common_keyvault_client_secret_secret_name="home-media-server-client-secret"
    azure_common_keyvault_vpn_wireguard_private_key_secret_name="vpn-private-key-secret"
    azure_common_keyvault_cloudflare_api_token_secret_name="home-media-server-cloudflare-api-token"
    azure_common_keyvault_cloudflare_zone_id_secret_name="home-media-server-cloudflare-zone-id"
    azure_common_keyvault_cloudflare_account_id_secret_name="home-media-server-cloudflare-account-id"
    timezone="Europe/London"
    transmission_vpn_provider_name="mullvad"
    transmission_vpn_provider_environment_variables=[]
    host_storage_config_dir="/srv/home-media-server/config"
    host_storage_config_capacity="5Gi"
    host_storage_media_dir="/srv/home-media-server/media"
    host_storage_media_capacity="600Gi"
    local_network_ip_address="192.168.50.109"
    ```

    See [`infrastructure/variables.tf`](infrastructure/variables.tf) for all variables and
    descriptions. Secret *values* live in Azure Key Vault; only their names go here.

1. Deploy:

    ``` shell
    task recreate
    ```

1. Configure the individual apps via their UIs.

## LAN access

Jellyfin's `jellyfin-lan` Service is `type: LoadBalancer`. k3s's built-in ServiceLB (klipper)
binds its ports **directly onto the host's LAN interface**, so clients such as an NVIDIA Shield
reach the server on its real ports with no forwarding layer:

| Port | Protocol | Purpose |
|---|---|---|
| 8096 | TCP | HTTP |
| 8920 | TCP | HTTPS |
| 7359 | UDP | Client auto-discovery |
| 1900 | UDP | DLNA/SSDP |

Give the host a fixed address — a DHCP reservation on the router against its MAC is simpler to
manage than static network configuration on the host.

If `ufw` is enabled, the pod and service CIDRs must be allowed or cluster networking breaks:

``` shell
sudo ufw allow from 10.42.0.0/16 to any
sudo ufw allow from 10.43.0.0/16 to any
sudo ufw allow 22,6443,8096,8920/tcp
sudo ufw allow 7359,1900/udp
```

## GPU scheduling

Pods that need the GPU set `runtimeClassName: nvidia` (see
[`helm/templates/jellyfin.yaml`](helm/templates/jellyfin.yaml)) alongside a
`nvidia.com/gpu` resource limit. The [`nvidia` RuntimeClass](helm/templates/runtime-class.yaml)
maps onto the containerd handler k3s configures, and `nvidia-device-plugin` advertises the GPU
as a schedulable resource.

To verify hardware transcoding end to end, start a transcode in Jellyfin and check that the
encoder is actually busy:

``` shell
nvidia-smi dmon      # the `enc` column must be non-zero
```

## Notes on the cluster lifecycle

k3s is a long-lived systemd service, not a disposable container. `task recreate` applies
infrastructure and upgrades the Helm release **against the existing cluster** — it does not
tear the cluster down first, as the previous k3d-based setup did.

To rebuild the cluster from scratch:

``` shell
task k3s:cluster:delete     # destructive, prompts for confirmation
task k3s:cluster:install
```
