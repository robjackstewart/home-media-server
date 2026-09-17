#!/usr/bin/env bash
# Used by the `data "external"` block in arc.tf. Terraform's `external` provider contract: read
# nothing from stdin (this program takes no query object), emit exactly one JSON object of
# string:string on stdout, nothing else - so every diagnostic goes to stderr instead.
#
# Usage: oidc-issuer.sh <resource-group> <cluster-name>
set -euo pipefail

resource_group="${1:?resource group is required}"
cluster_name="${2:?cluster name is required}"

issuer=$(az connectedk8s show \
  --resource-group "$resource_group" \
  --name "$cluster_name" \
  --query "oidcIssuerProfile.issuerUrl" \
  --output tsv)

if [ -z "$issuer" ] || [ "$issuer" = "None" ]; then
  echo "oidc-issuer.sh: cluster '$cluster_name' in '$resource_group' has no OIDC issuer URL - was it connected with --enable-oidc-issuer?" >&2
  exit 1
fi

printf '{"url": "%s"}\n' "$issuer"
