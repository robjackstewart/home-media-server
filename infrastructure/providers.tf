terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.29"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
    # Backs infrastructure/ci.tf - the CI identity GitHub Actions authenticates as via OIDC. Only
    # needed for that; nothing else in this config touches Entra ID objects directly.
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    # Backs the `data "external"` block in arc.tf that reads the Arc cluster's OIDC issuer URL
    # back out after arc-connect.sh has run.
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tfstate"
    storage_account_name = "robstewarttfstate"
    container_name       = "tfstate"
    key                  = "home-media-server.terraform.tfstate"
  }
}