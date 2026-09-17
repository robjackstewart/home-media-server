# The identity GitHub Actions authenticates as (via OIDC - no stored Azure credential in GitHub
# at all) to run `terraform apply` on every push to `main`, and `terraform plan` on every PR. This
# is what makes it possible to have no self-hosted runner on the home host at all: CI needs Azure
# access to apply this same Terraform config, but never touches the Kubernetes API directly (see
# the "Design decision" section of the implementation plan) - Flux, not CI, deploys the chart.
#
# Bootstrap note: this resource creates the very identity the CI workflow needs to run
# `terraform apply` at all, so it can only be created by a human running `task recreate` locally
# the first time (same as the Arc connect step in arc.tf) - CI can't create its own credentials.
# After that first apply, `terraform output` prints the three values
# (.github/workflows/deploy.yml's README section explains where to put them) and every
# subsequent apply, including from CI itself, just confirms this identity is unchanged.

resource "azuread_application" "ci" {
  display_name = "home-media-server-ci"
}

resource "azuread_service_principal" "ci" {
  client_id = azuread_application.ci.client_id
}

# One federated credential per GitHub Actions trigger this identity needs to authenticate for -
# each must match a workflow run's OIDC token subject exactly, so both are listed even though
# only two are actually used ((push to main) -> apply, (pull_request) -> plan).
resource "azuread_application_federated_identity_credential" "ci_push_main" {
  application_id = azuread_application.ci.id
  display_name   = "github-actions-push-main"
  description    = "home-media-server deploy.yml, push to main (terraform apply)"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:robjackstewart/home-media-server:ref:refs/heads/main"
}

resource "azuread_application_federated_identity_credential" "ci_pull_request" {
  application_id = azuread_application.ci.id
  display_name   = "github-actions-pull-request"
  description    = "home-media-server deploy.yml, any pull_request (terraform plan only)"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:robjackstewart/home-media-server:pull_request"
}

# Contributor covers creating/updating almost everything this config manages, but explicitly
# excludes managing role assignments (Microsoft.Authorization/roleAssignments/write) - User
# Access Administrator, scoped to the same resource group (not the whole subscription), covers
# just that gap: this config's own azurerm_role_assignment.arc_cluster_admin and the two grants
# below. A PR that only touches the chart or clusters/home/ never exercises this - Flux, not
# Terraform, deploys those - so in practice CI only ever needs these once something in
# infrastructure/ itself changes.
resource "azurerm_role_assignment" "ci_contributor" {
  scope                = azurerm_resource_group.home_media_server.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.ci.object_id
}

resource "azurerm_role_assignment" "ci_user_access_administrator" {
  scope                = azurerm_resource_group.home_media_server.id
  role_definition_name = "User Access Administrator"
  principal_id         = azuread_service_principal.ci.object_id
}

# Write access to this project's own vault - CI needs this to keep the Secrets/values ESO syncs
# up to date (the vpn_wireguard_private_key/comicvine_api_key/etc. azurerm_key_vault_secret
# resources in main.tf). Matches the access-policy model azurerm_key_vault.keyvault already uses
# (rbac_authorization_enabled = false), so this is a policy grant, not a role assignment.
resource "azurerm_key_vault_access_policy" "ci" {
  key_vault_id = azurerm_key_vault.keyvault.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azuread_service_principal.ci.object_id

  secret_permissions = [
    "Get",
    "Set",
    "List",
    "Delete",
  ]
}

# Read-only access to the *common* vault - CI needs this to read the WireGuard key, Hardcover
# token, ComicVine key and Tailscale bootstrap OAuth credentials it copies into the project vault
# above. Only granted if the common vault also uses the access-policy model and the principal
# running this apply has rights to modify its policies - if it's RBAC-based instead, grant "Key
# Vault Secrets User" there by hand (or via that vault's own Terraform, wherever it lives) instead
# of through this resource.
resource "azurerm_key_vault_access_policy" "ci_common_vault" {
  key_vault_id = data.azurerm_key_vault.common.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azuread_service_principal.ci.object_id

  secret_permissions = [
    "Get",
    "List",
  ]
}
