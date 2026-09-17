# Not secret - a managed identity's client ID is a public GUID, not a credential (the credential
# is the federated trust relationship itself, which never leaves Azure). Needed once, by hand,
# after the first `terraform apply`: paste it into
# clusters/home/external-secrets.yaml's serviceAccount.annotations, commit, push. See that file's
# own comment for why this can't be filled in ahead of time.
output "external_secrets_identity_client_id" {
  value       = azurerm_user_assigned_identity.external_secrets.client_id
  description = "Paste into clusters/home/external-secrets.yaml's azure.workload.identity/client-id annotation after the first apply."
}

output "arc_oidc_issuer_url" {
  value       = data.external.arc_oidc_issuer.result.url
  description = "The Arc-connected cluster's OIDC issuer URL - useful for troubleshooting workload identity, not needed day to day."
}

# Needed once, by hand, to wire up GitHub Actions OIDC (see infrastructure/ci.tf and
# .github/workflows/deploy.yml). None of these three are secret - the federated trust
# relationship they authenticate against is what actually gates access, not these IDs - but they
# have to be set as GitHub Actions repository variables (Settings -> Secrets and variables ->
# Actions -> Variables, not Secrets) for the workflow to use them:
#   gh variable set AZURE_CLIENT_ID --body "$(terraform output -raw ci_azure_client_id)"
#   gh variable set AZURE_TENANT_ID --body "$(terraform output -raw ci_azure_tenant_id)"
#   gh variable set AZURE_SUBSCRIPTION_ID --body "$(terraform output -raw ci_azure_subscription_id)"
output "ci_azure_client_id" {
  value       = azuread_application.ci.client_id
  description = "Set as the AZURE_CLIENT_ID GitHub Actions repository variable."
}

output "ci_azure_tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Set as the AZURE_TENANT_ID GitHub Actions repository variable."
}

output "ci_azure_subscription_id" {
  value       = var.azure_subscription_id
  description = "Set as the AZURE_SUBSCRIPTION_ID GitHub Actions repository variable."
}
