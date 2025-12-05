terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {
      resource_group_name  = "tfstate"
      storage_account_name = "robstewarttfstate"
      container_name       = "tfstate"
      key                  = "home-media-server.terraform.tfstate"
  }
}