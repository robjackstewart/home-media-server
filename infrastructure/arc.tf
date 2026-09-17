# Connects the k3s cluster to Azure Arc, installs Flux as the Microsoft-managed `microsoft.flux`
# extension, and wires up Workload Identity Federation so External Secrets Operator (installed
# in-cluster by Flux, see ../clusters/home/) can read this project's own Key Vault without any
# stored credential and without CI ever touching the cluster API directly. See the "Design
# decision: how does CI reach the cluster at all?" section of the implementation plan for why.

# azurerm 5.0 only auto-registers Microsoft.KeyVault (see the comment on resource_providers_to_register
# in providers.tf) - these three are needed for Arc/Flux and aren't registered by default either.
resource "azurerm_resource_provider_registration" "kubernetes" {
  name = "Microsoft.Kubernetes"
}

resource "azurerm_resource_provider_registration" "kubernetes_configuration" {
  name = "Microsoft.KubernetesConfiguration"
}

resource "azurerm_resource_provider_registration" "extended_location" {
  name = "Microsoft.ExtendedLocation"
}

locals {
  arc_cluster_name = var.arc_cluster_name
  # Built directly rather than read back via a data source - azurerm has no
  # `azurerm_arc_kubernetes_cluster` data source, only the resource type, and that resource
  # expects to *create* the ARM object itself (hand-installing agents via a generated key pair)
  # rather than adopt one `az connectedk8s connect` already created. This is the same
  # subscription/RG/name shape Azure documents for connectedClusters resource IDs.
  arc_cluster_id = "/subscriptions/${var.azure_subscription_id}/resourceGroups/${azurerm_resource_group.home_media_server.name}/providers/Microsoft.Kubernetes/connectedClusters/${local.arc_cluster_name}"
}

# One-time local bootstrap: connects k3s to Azure Arc with workload identity federation enabled,
# then patches the *live* k3s API server config to trust the resulting OIDC issuer and restarts
# k3s. Must run somewhere `~/.kube/config` for this cluster is reachable - i.e. locally on the
# host, the same constraint `task k3s:use-kube-context` already has. Only runs once in practice:
# `terraform_data` with no `triggers_replace` re-runs its provisioners only when the resource is
# first created, not on every subsequent `apply` (re-running `az connectedk8s connect`/`update` on
# every apply would be harmless since the script is idempotent, but restarting k3s on every apply
# would not be - `terraform apply -replace=terraform_data.arc_connect` is the deliberate way to
# force a re-run, e.g. after `task k3s:cluster:delete` + `install` rebuilds the node from scratch).
resource "terraform_data" "arc_connect" {
  # A destroy-time provisioner can only interpolate `self.*`, not other resources' attributes, so
  # the resource group/name it needs are captured here rather than read from
  # azurerm_resource_group.home_media_server directly in the destroy command below. Since these
  # values don't change in normal use, this also means the create-time provisioner below only
  # re-runs (see the resource-level comment above) if the RG or cluster name genuinely changes.
  triggers_replace = {
    resource_group = azurerm_resource_group.home_media_server.name
    cluster_name   = local.arc_cluster_name
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/arc-connect.sh"
    environment = {
      ARC_RESOURCE_GROUP = self.triggers_replace.resource_group
      ARC_LOCATION       = azurerm_resource_group.home_media_server.location
      ARC_CLUSTER_NAME   = self.triggers_replace.cluster_name
      REPO_ROOT          = "${path.module}/.."
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "az connectedk8s delete --yes --only-show-errors -g ${self.triggers_replace.resource_group} -n ${self.triggers_replace.cluster_name} || true"
  }

  depends_on = [
    azurerm_resource_provider_registration.kubernetes,
    azurerm_resource_provider_registration.kubernetes_configuration,
    azurerm_resource_provider_registration.extended_location,
  ]
}

# Reads back the OIDC issuer URL Azure generated during `arc-connect.sh` above. `depends_on` forces
# this to evaluate at apply time (after arc_connect has actually run) rather than during plan, which
# is what makes the external-data-source-depends_on pattern work here.
data "external" "arc_oidc_issuer" {
  program    = ["bash", "${path.module}/scripts/oidc-issuer.sh", azurerm_resource_group.home_media_server.name, local.arc_cluster_name]
  depends_on = [terraform_data.arc_connect]
}

resource "azurerm_arc_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = local.arc_cluster_id
  extension_type = "microsoft.flux"
  # Cluster-scoped extension, not namespace-scoped - required for release_namespace.
  release_namespace = "flux-system"

  identity {
    type = "SystemAssigned"
  }

  configuration_settings = {
    # The extension enforces multi-tenancy (each Flux Kustomization confined to its own
    # namespace) by default, which would block the cross-namespace GitRepository sourceRef every
    # HelmRelease under clusters/home/ uses.
    "multiTenancy.enforce" = "false"
  }

  depends_on = [terraform_data.arc_connect]
}

# The identity External Secrets Operator's pods authenticate as, via Workload Identity Federation -
# no client secret is ever stored anywhere, in or out of the cluster.
resource "azurerm_user_assigned_identity" "external_secrets" {
  name                = "home-media-server-external-secrets"
  resource_group_name = azurerm_resource_group.home_media_server.name
  location            = azurerm_resource_group.home_media_server.location
}

resource "azurerm_federated_identity_credential" "external_secrets" {
  name                      = "home-media-server-external-secrets"
  user_assigned_identity_id = azurerm_user_assigned_identity.external_secrets.id
  issuer                    = data.external.arc_oidc_issuer.result.url
  # Must match the ServiceAccount ESO's own Helm chart creates - see
  # clusters/home/external-secrets.yaml, which pins `serviceAccount.name: external-secrets` in
  # namespace `external-secrets` explicitly so this subject is never at the mercy of the chart's
  # fullname template changing.
  subject  = "system:serviceaccount:external-secrets:external-secrets"
  audience = ["api://AzureADTokenExchange"]
}

# The project vault (azurerm_key_vault.keyvault in main.tf) uses the access-policy model, not
# Azure RBAC (rbac_authorization_enabled = false there), so this grants access the same way the
# current user's own access_policy block does, not via azurerm_role_assignment.
resource "azurerm_key_vault_access_policy" "external_secrets" {
  key_vault_id = azurerm_key_vault.keyvault.id
  tenant_id    = azurerm_user_assigned_identity.external_secrets.tenant_id
  object_id    = azurerm_user_assigned_identity.external_secrets.principal_id

  secret_permissions = [
    "Get",
    "List",
  ]
}

# Lets the signed-in principal running `terraform apply` (or whoever `az login`s later) manage the
# cluster remotely via `az connectedk8s proxy` ("cluster connect") - unrelated to CI, which never
# gets any role on the cluster at all (see infrastructure/ci.tf, added in a later PR).
resource "azurerm_role_assignment" "arc_cluster_admin" {
  scope                = local.arc_cluster_id
  role_definition_name = "Azure Arc Kubernetes Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id

  depends_on = [terraform_data.arc_connect]
}

# Points Flux at this repo, pinned to a specific commit rather than following `main` directly, so
# a chart change is never reconciled before the infrastructure it depends on (the Key Vault
# secrets above) has actually been written by this same apply. `task recreate` and CI both pass
# `-var git_revision=$(git rev-parse HEAD)` - see README "Deploying".
resource "azurerm_arc_kubernetes_flux_configuration" "home" {
  name       = "home-media-server"
  cluster_id = local.arc_cluster_id
  namespace  = "flux-system"
  scope      = "cluster"

  git_repository {
    url             = "https://github.com/robjackstewart/home-media-server"
    reference_type  = "commit"
    reference_value = var.git_revision
  }

  kustomizations {
    name                       = "cluster"
    path                       = "./clusters/home"
    garbage_collection_enabled = true
    sync_interval_in_seconds   = 60
  }

  depends_on = [
    azurerm_arc_kubernetes_cluster_extension.flux,
    azurerm_key_vault_secret.tailscale_operator_oauth_client_id,
    azurerm_key_vault_secret.tailscale_operator_oauth_client_secret,
    azurerm_key_vault_secret.vpn_wireguard_private_key,
    azurerm_key_vault_secret.comicvine_api_key,
    azurerm_key_vault_secret.rreading_glasses_hardcover_auth,
    azurerm_key_vault_secret.rreading_glasses_postgres_password,
    azurerm_key_vault_secret.infrastructure_values,
    azurerm_key_vault_access_policy.external_secrets,
  ]
}
