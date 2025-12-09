terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.110.0"
    }
    azapi = {
      source = "Azure/azapi"
    }
  }

   backend "azurerm" {
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  skip_provider_registration=true
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  # Credentials are provided via environment / OIDC in CI (ARM_* or Azure CLI).
  # Do not hard-code client_id/client_secret/subscription/tenant here when using GitHub OIDC.
}
provider "azapi" {}