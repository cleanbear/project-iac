#############  IPL-Eximius Prod Infra ###########################

locals {

  tags={
    Environment = "Prod"
    Studio = "testing"
    Division = "my"
    Account_Manager = "Guru Kalyan"
  }

}

#####################################################################################

###################  Virtual Network ###################

module "Vnet" {
  source              = "Azure/vnet/azurerm"
  version             = "4.1.0"
  resource_group_name = var.resourceGroupName
  vnet_location       = var.location
  vnet_name           = var.vnet_name
  use_for_each        = true
  address_space       = var.vnet_address_space
  subnet_names        = var.subnet_names
  subnet_prefixes     = var.subnet_prefixes
   subnet_service_endpoints = {
    "${var.subnet_names[0]}" = ["Microsoft.KeyVault", "Microsoft.Storage"]
    "${var.subnet_names[1]}" = ["Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
  }
  tags = local.tags
}

#####################################################################################

###################  Azure Container Registry ###################

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  location            = var.location
  resource_group_name = var.resourceGroupName
  admin_enabled       = true
  sku                 = "Basic"
  anonymous_pull_enabled = false
  public_network_access_enabled = var.public_network_access_enabled

  tags = local.tags
}

#####################################################################################

###################  AKS  ###################
module "aks" {
  source                               = "Azure/aks/azurerm"
  version                              = "9.4.1"
  resource_group_name                  = var.resourceGroupName
  private_cluster_enabled              = false
  cluster_name                         = var.aks_cluster_name
  location                             = var.location
  agents_availability_zones            = var.aks_agents_availability_zones
  role_based_access_control_enabled    = true
  rbac_aad                             = false
  vnet_subnet_id                       = module.Vnet.vnet_subnets[0]
  network_policy                       = "azure"
  net_profile_dns_service_ip           = var.net_profile_dns_service_ip
  net_profile_service_cidr             = var.net_profile_service_cidr
  network_plugin                       = "azure"
  cluster_log_analytics_workspace_name = "gk-eastus2-prod-loganalyticsws"
  log_analytics_workspace_enabled      = false
  agents_min_count                     = 1
  agents_max_count                     = 1
  agents_count                         = null
  agents_pool_name                     = "gknodepool"
  agents_size                          =  "Standard_B2s"  # 2 cores, 8GB RAM (meets AKS min requirements)   
  enable_auto_scaling                  = true
  key_vault_secrets_provider_enabled   = true
  storage_profile_blob_driver_enabled  = true
  storage_profile_disk_driver_enabled  = true
  prefix                               = var.aks_prefix
  attached_acr_id_map = {
    acr = azurerm_container_registry.acr.id
  }
  api_server_authorized_ip_ranges =  var.allowed_ip_addresses
  
  tags = local.tags

  depends_on = [azurerm_container_registry.acr]
 }

#####################################################################################

###################  Key Vault  ###################

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "keyvault" {
  name                     = var.key_vault_name
  location                 = var.location
  resource_group_name      = var.resourceGroupName
  tenant_id                = data.azurerm_client_config.current.tenant_id
  sku_name                 = "standard"
  purge_protection_enabled    = true
  soft_delete_retention_days  = 7

  network_acls {
    default_action             = "Deny"
    bypass                     = "AzureServices"
    ip_rules                   = var.allowed_ip_addresses
    virtual_network_subnet_ids = module.Vnet.vnet_subnets
  }
  tags = local.tags
}

resource "azurerm_private_dns_zone" "main" {
  name                = var.azurerm_private_dns_zone_kv_name
  resource_group_name = var.resourceGroupName

  tags = local.tags
}

resource "azurerm_private_endpoint" "pe_kv" {
  name                = var.azurerm_private_endpoint_kv_name
  location            = var.location
  resource_group_name = var.resourceGroupName
  subnet_id           = module.Vnet.vnet_subnets[0]

  private_dns_zone_group {
    name                 = var.private_dns_zone_group_kv_name
    private_dns_zone_ids = [azurerm_private_dns_zone.main.id]
  }

  private_service_connection {
    name                           = var.private_service_connection_kv_name
    private_connection_resource_id = azurerm_key_vault.keyvault.id
    is_manual_connection           = false
    subresource_names              = ["Vault"]
  }
  tags = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_private_dns_zone_virtual_network_link1" {
  name                  = var.azurerm_private_dns_zone_virtual_network_link_kv_name
  private_dns_zone_name = azurerm_private_dns_zone.main.name
  resource_group_name   = var.resourceGroupName
  virtual_network_id    = module.Vnet.vnet_id

  tags = local.tags
}


resource "azurerm_key_vault_access_policy" "kvpolicy" {
  key_vault_id       = azurerm_key_vault.keyvault.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = module.aks.kubelet_identity[0].object_id
  key_permissions    = ["Get"]
  secret_permissions = ["Get"]
}

resource "azurerm_key_vault_access_policy" "kvpolicytf" {
  key_vault_id       = azurerm_key_vault.keyvault.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = data.azurerm_client_config.current.object_id
  key_permissions    = ["Get", "Create"]
  secret_permissions = ["Get", "Set"]
}

resource "azurerm_key_vault_access_policy" "kvpolicyuser" {
  key_vault_id       = azurerm_key_vault.keyvault.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = var.object_id
  key_permissions    = ["Get", "Create"]
  secret_permissions = ["Get", "Set"]
}

resource "azurerm_key_vault_secret" "gk_secrets" {
  count        = length(var.kvsecrets)
  name         = var.kvsecrets[count.index].name
  value        = var.kvsecrets[count.index].value
  key_vault_id = azurerm_key_vault.keyvault.id
  depends_on   = [azurerm_key_vault_access_policy.kvpolicytf]
  lifecycle {
    ignore_changes = [
      value
    ]
  }
}
#####################################################################################

##################  Storage Account (Azure Blob) ###################
resource "azurerm_storage_account" "st" {
  name                     = var.azurerm_storage_account_name
  resource_group_name      = var.resourceGroupName
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = true
  blob_properties {
    delete_retention_policy {
      days = 10
    }
    # cors_rule {
    #   # Use empty lists when no CORS headers/origins are required.
    #   # To allow specific origins, replace [] with e.g. ["https://example.com"]
    #   allowed_headers    = [""]
    #   allowed_methods    = ["GET", "HEAD", "POST", "OPTIONS", "PUT", "PATCH"]
    #   allowed_origins    = []
    #   exposed_headers    = [""]
    #   max_age_in_seconds = 0
    # }
  }
  network_rules {
    default_action = "Allow"
    ip_rules       = var.allowed_ip_addresses
     bypass         = ["AzureServices"]
  }
  tags = local.tags
}

resource "azurerm_storage_container" "blob" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.st.name
  container_access_type = "blob"
}

resource "azurerm_private_dns_zone" "pdns_st" {
  name                = var.azurerm_private_dns_zone_storage_name
  resource_group_name = var.resourceGroupName

  tags = local.tags
}

resource "azurerm_private_endpoint" "pep_st" {
  name                = var.azurerm_private_endpoint_storage_name
  location            = var.location
  resource_group_name = var.resourceGroupName
  subnet_id           = module.Vnet.vnet_subnets[0]

  private_service_connection {
    name                           = var.private_service_connection_storage_name
    private_connection_resource_id = azurerm_storage_account.st.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = var.private_dns_zone_group_storage_name
    private_dns_zone_ids = [azurerm_private_dns_zone.pdns_st.id]
  }
  tags = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_vnet_lnk_sta" {
  name                  = var.azurerm_private_dns_zone_virtual_network_link_storage_name
  resource_group_name   = var.resourceGroupName
  private_dns_zone_name = azurerm_private_dns_zone.pdns_st.name
  virtual_network_id    = module.Vnet.vnet_id
  tags = local.tags
}


 resource "azurerm_role_assignment" "assign_identity_storage_blob_data_contributor" {
   scope                = azurerm_storage_account.st.id
   role_definition_name = "Contributor"
   principal_id         = module.aks.kubelet_identity[0].object_id
 }
