# Home Media Server

A Jellyfin-centred media stack running on **native k3s** on bare-metal Linux, with the NVIDIA
GPU attached directly for hardware transcoding, exposed to the LAN via k3s's built-in ServiceLB
and to your own devices, wherever they are, over a private [Tailscale](https://tailscale.com)
tailnet. Nothing is reachable from the public internet.

## Requirements

1. A Tailscale account and tailnet, with MagicDNS and HTTPS Certificates enabled
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

1. **k3s** — installed with the declarative config in [`k3s/config.yaml`](k3s/config.yaml),
   which disables Traefik (this chart uses no in-cluster Ingress controller - see
   [Remote access](#remote-access)) and labels the node as GPU-capable:

    ``` shell
    task k3s:cluster:install
    task k3s:use-kube-context
    ```

1. **Confirm k3s found the GPU runtime.** k3s writes the nvidia runtime into containerd's
   config itself once it detects the host toolkit — there is no custom node image to build:

    ``` shell
    task k3s:gpu:check
    ```

Host storage needs no step of its own. The `config` and `media` directories are created and
chowned to `puid`/`guid` by a pre-install/pre-upgrade hook in the chart
([`helm/templates/host-storage.bootstrap.yaml`](helm/templates/host-storage.bootstrap.yaml)),
so `task recreate` prepares them. Only data you restore onto the host by hand needs its own
`chown -R`, since the release cannot know about files it did not put there.

## Getting started

1. Install the [Task CLI](https://taskfile.dev/installation/), plus `helm`, `kubectl`,
   `terraform` and `az`. `task environment:check` verifies all of them.
1. Check the environment. This errors if any tooling, the k3s service, or the GPU is missing:

    ``` shell
    task environment:check
    ```

1. Create [`config/variables.tfvars`](config/variables.tfvars) and populate it. For example:

    ```
    azure_subscription_id="<your-azure-subscription-id>"
    azure_common_keyvault_name="terraform-kv"
    azure_common_keyvault_resource_group="tfstate"
    azure_common_keyvault_vpn_wireguard_private_key_secret_name="vpn-private-key-secret"
    azure_common_keyvault_tailscale_terraform_oauth_client_id_secret_name="home-media-server-tailscale-terraform-oauth-client-id"
    azure_common_keyvault_tailscale_terraform_oauth_client_secret_secret_name="home-media-server-tailscale-terraform-oauth-client-secret"
    azure_common_keyvault_tailscale_operator_oauth_client_id_secret_name="home-media-server-tailscale-operator-oauth-client-id"
    azure_common_keyvault_tailscale_operator_oauth_client_secret_secret_name="home-media-server-tailscale-operator-oauth-client-secret"
    tailscale_tailnet_name="tailxxxx.ts.net"
    timezone="Europe/London"
    transmission_vpn_provider_name="mullvad"
    transmission_vpn_provider_environment_variables=[]
    host_storage_config_dir="/srv/home-media-server/config"
    host_storage_config_capacity="5Gi"
    host_storage_media_dir="/srv/home-media-server/media"
    host_storage_media_capacity="600Gi"
    ```

    See [`infrastructure/variables.tf`](infrastructure/variables.tf) for all variables and
    descriptions, and [Remote access](#remote-access) below for how to create the four
    Tailscale-related secrets. Secret *values* live in Azure Key Vault; only their names go here.

1. Deploy:

    ``` shell
    task recreate
    ```

1. Configure the individual apps via their UIs.

## Remote access

Every app is exposed individually to your tailnet by the [Tailscale Kubernetes
operator](https://tailscale.com/kb/1236/kubernetes-operator) (`helm/templates/tailscale.yaml`,
plus a `tailscaleIngress` template helper each app calls) at
`https://<subdomain>.<your-tailnet>` — e.g. `https://jellyfin.tailxxxx.ts.net` — with a
Tailscale-issued TLS certificate. Nothing is reachable except from a device signed into the
tailnet; there is no public DNS record and no port exposed to the internet.

**One-time setup**, before your first `task recreate`:

1. In the Tailscale admin console → **DNS**, enable **MagicDNS** and **HTTPS Certificates**.
   The resulting `<tailnet>.ts.net` suffix is `tailscale_tailnet_name` in
   `config/variables.tfvars`.
1. Create two OAuth clients (Settings → OAuth clients):
   - `terraform`, scoped to **policy file: write**. Used by the `tailscale_acl` resource in
     `infrastructure/main.tf` to manage the tailnet's ACL — tailnet membership is the whole
     authorization boundary, so this is what grants access to your devices.
   - `k8s-operator`, scoped to **write** on `General/Services`, `Devices/Core` and
     `Keys/Auth Keys`, each tagged `tag:k8s-operator`.
1. Put all four values (two client IDs, two client secrets) in your common Key Vault, and
   reference their secret names from the four `azure_common_keyvault_tailscale_*_secret_name`
   variables.
1. Install Tailscale on every device that should reach the server, and sign in.

`tailscale_acl` **replaces the entire tailnet policy file** on apply - if your tailnet already
has hand-written ACL rules, copy them out of the admin console first and fold them into
`infrastructure/main.tf` before running `task recreate`.

**Migrating an existing deployment from the old Cloudflare Tunnel setup:** the Gateway API CRDs
that setup installed are not managed by this chart at all any more and won't be removed by
`task recreate`. Delete them once, by hand:

``` shell
kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
```

You'll also need to update the hostname baked into a few apps' own configuration, since it isn't
templated by this chart: Heimdall's dashboard tiles, Jellyfin's published server URL (Dashboard →
Networking), Seerr's application URL, and Home Assistant's `external_url`.

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
`nvidia.com/gpu` resource limit. `nvidia-device-plugin` advertises the GPU as a schedulable
resource.

The `nvidia` RuntimeClass itself is **not** part of this chart. k3s creates it automatically
when it detects `nvidia-container-runtime` on the host, from its own bundled addon at
`/var/lib/rancher/k3s/server/manifests/runtimes.yaml`. That object carries no Helm ownership
metadata and is continuously reconciled by the k3s addon controller, so a chart-managed copy
cannot coexist with it - `helm upgrade --install` aborts with an ownership error. Confirm k3s
made it with `kubectl get runtimeclass nvidia`.

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
