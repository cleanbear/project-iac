locals {

  tags={
    Environment = "dev-qa"
    Studio = "gk"
    Division = "gk"
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
    "${var.subnet_names[0]}" = ["Microsoft.KeyVault", "Microsoft.Storage"]
    "${var.subnet_names[1]}" = ["Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
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
  sku                 = "Basic"
  anonymous_pull_enabled = false
  public_network_access_enabled = var.public_network_access_enabled

  tags = local.tags
}

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
    ip_rules                   = []
    virtual_network_subnet_ids = [module.Vnet.vnet_subnets[0], module.Vnet.vnet_subnets[1]]
  }
  tags = local.tags
}

resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
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
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }

  private_service_connection {
    name                           = var.private_service_connection_kv_name
    private_connection_resource_id = azurerm_key_vault.keyvault.id
    is_manual_connection           = false
    subresource_names              = ["Vault"]
  }
  tags = local.tags

  depends_on = [ module.Vnet, azurerm_key_vault.keyvault, azurerm_private_dns_zone.kv ]
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv_private_dns_zone_virtual_network_link1" {
  name                  = var.azurerm_private_dns_zone_virtual_network_link_kv_name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  resource_group_name   = var.resourceGroupName
  virtual_network_id    = module.Vnet.vnet_id

  tags = local.tags

  depends_on = [ module.Vnet, azurerm_private_dns_zone.kv ]
}

resource "azurerm_key_vault_access_policy" "kvpolicy" {
  key_vault_id       = azurerm_key_vault.keyvault.id
  tenant_id          = data.azurerm_client_config.current.tenant_id
  object_id          = module.aks.kubelet_identity[0].object_id
  key_permissions    = ["Get"]
  secret_permissions = ["Get"]

  depends_on = [ module.aks ]
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

##################  Storage Account (Azure Blob) ###################
resource "azurerm_storage_account" "st" {
  name                     = var.azurerm_storage_account_name
  resource_group_name      = var.resourceGroupName
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  allow_nested_items_to_be_public = true
  # blob_properties {
  #   delete_retention_policy {
  #     days = 10
  #   }
  #   # cors_rule {
  #   #   # Use empty lists when no CORS headers/origins are required.
  #   #   # To allow specific origins, replace [] with e.g. ["https://example.com"]
  #   #   allowed_headers    = [""]
  #   #   allowed_methods    = ["GET", "HEAD", "POST", "OPTIONS", "PUT", "PATCH"]
  #   #   allowed_origins    = []
  #   #   exposed_headers    = [""]
  #   #   max_age_in_seconds = 0
  #   # }
  # }
  network_rules {
    default_action             = "Deny"
    ip_rules       = []
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [module.Vnet.vnet_subnets[0], module.Vnet.vnet_subnets[1]]
  }
  tags = local.tags
}

resource "azurerm_storage_container" "blob" {
  name                  = var.storage_container_name
  storage_account_name  = azurerm_storage_account.st.name
  container_access_type = "blob"

  depends_on = [ azurerm_storage_account.st ]
}

resource "azurerm_private_dns_zone" "pdns_st" {
  name                = "privatelink.blob.core.windows.net"
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

  depends_on = [ module.Vnet, azurerm_storage_account.st, azurerm_private_dns_zone.pdns_st ]
}

resource "azurerm_private_dns_zone_virtual_network_link" "dns_vnet_lnk_sta" {
  name                  = var.azurerm_private_dns_zone_virtual_network_link_storage_name
  resource_group_name   = var.resourceGroupName
  private_dns_zone_name = azurerm_private_dns_zone.pdns_st.name
  virtual_network_id    = module.Vnet.vnet_id
  tags = local.tags

  depends_on = [ module.Vnet, azurerm_private_dns_zone.pdns_st ]
}

resource "azurerm_role_assignment" "assign_identity_storage_blob_data_contributor" {
  scope                = azurerm_storage_account.st.id
  role_definition_name = "Contributor"
  principal_id         = module.aks.kubelet_identity[0].object_id

  depends_on = [ module.aks, azurerm_storage_account.st ]
}
# ###################  Log Analytics Workspace ###################

# resource "azurerm_log_analytics_workspace" "la" {
#   name                = var.log_analytics_workspace_name
#   location            = var.location
#   resource_group_name = var.resourceGroupName
#   sku                 = "PerGB2018"
#   retention_in_days   = var.log_analytics_retention_days

#   tags = local.tags
# }
###################  AKS  ###################
module "aks" {
  source                               = "Azure/aks/azurerm"
  version                              = "9.4.1"
  resource_group_name                  = var.resourceGroupName
  private_cluster_enabled              = false
  cluster_name                         = var.aks_cluster_name
  sku_tier                             = "Standard"
  location                             = var.location
  agents_availability_zones            = var.aks_agents_availability_zones
  role_based_access_control_enabled    = true
  rbac_aad                             = false
  vnet_subnet_id                       = module.Vnet.vnet_subnets[1]
  network_policy                       = "azure"
  network_plugin                       = "azure"
  cluster_log_analytics_workspace_name = var.log_analytics_workspace_name
  log_analytics_workspace_enabled      = true
  agents_min_count                     = 1
  agents_max_count                     = 2
  agents_count                         = null
  agents_pool_name                     = "gknodepool"
  agents_size                          = "Standard_D2ps_V5"
  enable_auto_scaling                  = true
  key_vault_secrets_provider_enabled   = true
  storage_profile_blob_driver_enabled  = true
  storage_profile_disk_driver_enabled  = true
  prefix                               = var.aks_prefix
  attached_acr_id_map = {
    acr = azurerm_container_registry.acr.id
  }
  api_server_authorized_ip_ranges =  []
  
  tags = local.tags

  depends_on = [azurerm_container_registry.acr, module.Vnet.vnet_subnets, azurerm_log_analytics_workspace.la]
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
###################  Application Insights for APIM ###################

resource "azurerm_application_insights" "ai_apim" {
  name                = "${var.apim_name}-appinsights"
  location            = var.location
  resource_group_name = var.resourceGroupName
  application_type    = "Node.JS"

  tags = local.tags
}

# Create APIM logger that points to App Insights (using azapi to avoid provider schema mismatches)
# resource "azapi_resource" "apim_logger" {
#   type      = "Microsoft.ApiManagement/service/loggers@2021-08-01"
#   name      = "appinsights-logger"
#   parent_id = azurerm_api_management.apim.id

#   body = jsonencode({
#     properties = {
#       loggerType  = "applicationinsights"
#       description = "Application Insights logger for APIM"
#       credentials = {
#         instrumentationKey = azurerm_application_insights.ai_apim.instrumentation_key
#       }
#     }
#   })

#   depends_on = [azurerm_api_management.apim, azurerm_application_insights.ai_apim]
# }

# # Create APIM diagnostic that uses the above logger (sends telemetry to App Insights)
# resource "azapi_resource" "apim_ai_diag" {
#   type      = "Microsoft.ApiManagement/service/diagnostics@2021-08-01"
#   name      = "appinsights-diagnostic"
#   parent_id = azurerm_api_management.apim.id

#   body = jsonencode({
#     properties = {
#       enabled   = true
#       alwaysLog = "allErrors"
#       loggerId  = azapi_resource.apim_logger.id
#       sampling  = { sample = 100 }
#       frontend  = { request = { headers = [ "*" ] }, response = { headers = [ "*" ] } }
#       backend   = { request = { headers = [ "*" ] }, response = { headers = [ "*" ] } }
#     }
#   })

#   depends_on = [azapi_resource.apim_logger, azurerm_api_management.apim]
# }