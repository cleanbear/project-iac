locals {

  tags={
    Environment = "dev-qa"
    Studio = "mgk"
    Division = "mgk"
    Account_Manager = "Guru kalyan"
  }
}
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
    "${var.subnet_names[0]}" = ["Microsoft.KeyVault"]
    "${var.subnet_names[1]}" = ["Microsoft.KeyVault"]
    "${var.subnet_names[2]}" = ["Microsoft.KeyVault"]
  }
  tags = local.tags
}

###################  Azure Container Registry ###################

resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  location            = var.location
  resource_group_name = var.resourceGroupName
  admin_enabled       = true
  sku                 = "Standard"
  tags = local.tags
}

###################  API Management ###################

resource "azurerm_api_management" "apim" {
  name                = var.apim_name
  location            = var.location
  resource_group_name = var.resourceGroupName
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku

  tags = local.tags
}


###################  Key Vault + Private Endpoint ###################

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                = var.key_vault_name
  location            = var.location
  resource_group_name = var.resourceGroupName
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  tags = local.tags
}

# Private DNS zone for Key Vault private endpoint
resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resourceGroupName
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_link" {
  name                  = var.azurerm_private_dns_zone_virtual_network_link_kv_name
  resource_group_name   = var.resourceGroupName
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = module.Vnet.vnet_id
  registration_enabled  = false

  depends_on = [azurerm_private_dns_zone.kv, module.Vnet]
}

# Private endpoint for Key Vault using subnet[0]
resource "azurerm_private_endpoint" "kv_pe" {
  name                = var.azurerm_private_endpoint_kv_name
  location            = var.location
  resource_group_name = var.resourceGroupName
  subnet_id           = module.Vnet.vnet_subnets[0]

  private_service_connection {
    name                           = var.private_service_connection_kv_name
    private_connection_resource_id = azurerm_key_vault.kv.id
    is_manual_connection           = false
    subresource_names              = ["vault"]
  }

  private_dns_zone_group {
    name                 = var.private_dns_zone_group_kv_name
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
}

resource "azurerm_key_vault_access_policy" "kvpolicytf" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = data.azurerm_client_config.current.object_id
  key_permissions    = ["Get", "Create"]
  secret_permissions = ["Get", "Set", "List"]
}

resource "azurerm_key_vault_access_policy" "kvpolicyuser" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = var.object_id
  key_permissions    = ["Get", "Create", "List"]
  secret_permissions = ["Get", "Set", "List"]
}

resource "azurerm_key_vault_access_policy" "kvpolicyaks" {
  key_vault_id       = azurerm_key_vault.kv.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = module.aks.kubelet_identity[0].object_id
  key_permissions    = ["Get"]
  secret_permissions = ["Get", "List"]

  depends_on = [ module.aks ]
}


###################  Storage Account + Private Endpoint (use subnet[0]) ###################

resource "azurerm_storage_account" "storage" {
  name                     = var.azurerm_storage_account_name
  resource_group_name      = var.resourceGroupName
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # network_rules {
  #   default_action = "Deny"
  #   bypass         = ["AzureServices"]
  # }

  tags = local.tags
}

resource "azurerm_storage_container" "container" {
  name                  = var.storage_container_name
  storage_account_name    = azurerm_storage_account.storage.name
  container_access_type = "private"

  depends_on = [ azurerm_storage_account.storage ]
}

resource "azurerm_private_dns_zone" "storage" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = var.resourceGroupName
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_link" {
  name                  = var.azurerm_private_dns_zone_virtual_network_link_storage_name
  resource_group_name   = var.resourceGroupName
  private_dns_zone_name = azurerm_private_dns_zone.storage.name
  virtual_network_id    = module.Vnet.vnet_id
  registration_enabled  = false

  depends_on = [azurerm_private_dns_zone.storage, module.Vnet]
}

resource "azurerm_private_endpoint" "storage_pe" {
  name                = var.azurerm_private_endpoint_storage_name
  location            = var.location
  resource_group_name = var.resourceGroupName
  subnet_id           = module.Vnet.vnet_subnets[0]

  private_service_connection {
    name                           = var.private_service_connection_storage_name
    private_connection_resource_id = azurerm_storage_account.storage.id
    is_manual_connection           = false
    subresource_names              = ["blob"]
  }

  private_dns_zone_group {
    name                 = var.private_dns_zone_group_storage_name
    private_dns_zone_ids = [azurerm_private_dns_zone.storage.id]
  }

  depends_on = [ module.Vnet, azurerm_storage_account.storage, azurerm_private_dns_zone.storage ]
}

module "aks" {
  source                               = "Azure/aks/azurerm"
  version                              = "9.4.1"
  sku_tier                             = "Standard"
  resource_group_name                  = var.resourceGroupName
  cluster_name                         = var.aks_cluster_name
  location                             = var.location
  agents_availability_zones            = var.aks_agents_availability_zones
  vnet_subnet_id                       = module.Vnet.vnet_subnets[1]
  role_based_access_control_enabled    = false
  rbac_aad                             = false
  network_policy                       = "azure"
  network_plugin                       = "azure"
  cluster_log_analytics_workspace_name = var.log_analytics_ws_name #which analytics WS is it referring to?
  log_analytics_workspace_enabled      = true
  agents_min_count                     = 1
  agents_max_count                     = 2
  agents_pool_name                     = "mgkpool"
  agents_size                          = "Standard_D2ps_V5"
  enable_auto_scaling                  = true
  prefix                               = "mgk"
  attached_acr_id_map                  = {
    acr = azurerm_container_registry.acr.id
  }

  tags = local.tags

  depends_on = [ azurerm_container_registry.acr ]
}
