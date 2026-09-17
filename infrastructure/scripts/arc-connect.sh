#!/usr/bin/env bash
# One-time local bootstrap, run as a `local-exec` provisioner by `terraform_data.arc_connect` in
# arc.tf. Must run where `~/.kube/config` for this cluster is reachable - i.e. on the host itself,
# the same constraint `task k3s:use-kube-context` already has. Not something CI does; CI only
# calls Azure's own APIs (see the "Design decision" section of the implementation plan).
#
# 1. Connects (or updates) this k3s cluster's Azure Arc registration, with workload identity
#    federation enabled - safe to re-run: `connect` on an unregistered cluster, `update` on one
#    already connected.
# 2. Reads back the OIDC issuer URL Azure just generated for it.
# 3. Merges that into a copy of k3s/config.yaml (via k3s/workload-identity.yaml.tmpl) and installs
#    it as the live /etc/rancher/k3s/config.yaml, restarting k3s only if the merged content
#    actually changed - so re-running this script is a no-op once workload identity is enabled.
set -euo pipefail

: "${ARC_RESOURCE_GROUP:?ARC_RESOURCE_GROUP is required}"
: "${ARC_LOCATION:?ARC_LOCATION is required}"
: "${ARC_CLUSTER_NAME:?ARC_CLUSTER_NAME is required}"
: "${REPO_ROOT:?REPO_ROOT is required}"

echo "arc-connect: connecting '$ARC_CLUSTER_NAME' in '$ARC_RESOURCE_GROUP' to Azure Arc..." >&2

az extension add --name connectedk8s --only-show-errors --upgrade >/dev/null 2>&1 || true

if az connectedk8s show --resource-group "$ARC_RESOURCE_GROUP" --name "$ARC_CLUSTER_NAME" \
  --only-show-errors >/dev/null 2>&1; then
  az connectedk8s update \
    --resource-group "$ARC_RESOURCE_GROUP" \
    --name "$ARC_CLUSTER_NAME" \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --only-show-errors
else
  az connectedk8s connect \
    --resource-group "$ARC_RESOURCE_GROUP" \
    --name "$ARC_CLUSTER_NAME" \
    --location "$ARC_LOCATION" \
    --kube-config "$HOME/.kube/config" \
    --kube-context default \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --only-show-errors
fi

issuer=$(az connectedk8s show \
  --resource-group "$ARC_RESOURCE_GROUP" \
  --name "$ARC_CLUSTER_NAME" \
  --query "oidcIssuerProfile.issuerUrl" \
  --output tsv)

if [ -z "$issuer" ] || [ "$issuer" = "None" ]; then
  echo "arc-connect: connectedk8s reported no OIDC issuer URL after connect/update" >&2
  exit 1
fi
echo "arc-connect: OIDC issuer is $issuer" >&2

k3s_config_dir="$REPO_ROOT/k3s"
merged=$(mktemp)
trap 'rm -f "$merged"' EXIT

# Plain concatenation is safe here: config.yaml's top-level keys (disable, node-label,
# write-kubeconfig-mode, resolv-conf) and the workload-identity fragment's only key
# (kube-apiserver-arg) never collide, so two appended YAML mappings read back as one.
cat "$k3s_config_dir/config.yaml" >"$merged"
sed "s|__OIDC_ISSUER_URL__|$issuer|" "$k3s_config_dir/workload-identity.yaml.tmpl" >>"$merged"

if sudo test -f /etc/rancher/k3s/config.yaml && sudo diff -q "$merged" /etc/rancher/k3s/config.yaml >/dev/null 2>&1; then
  echo "arc-connect: /etc/rancher/k3s/config.yaml already up to date, not restarting k3s" >&2
  exit 0
fi

echo "arc-connect: installing merged k3s config and restarting k3s..." >&2
sudo mkdir -p /etc/rancher/k3s
sudo cp "$merged" /etc/rancher/k3s/config.yaml
sudo cp "$k3s_config_dir/resolv.conf" /etc/rancher/k3s/resolv.conf
sudo systemctl restart k3s

# Give the API server a moment to come back before Terraform's next step (the `data "external"`
# read of this same issuer URL, and everything downstream of it) tries to use the cluster again.
for _ in $(seq 1 30); do
  if kubectl --kubeconfig "$HOME/.kube/config" get --raw /healthz >/dev/null 2>&1; then
    echo "arc-connect: k3s API server is back up" >&2
    exit 0
  fi
  sleep 2
done

echo "arc-connect: k3s did not come back healthy within 60s of restart - check 'systemctl status k3s'" >&2
exit 1
