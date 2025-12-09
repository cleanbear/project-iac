
output "cluster_identity" {
  value = module.aks.kubelet_identity[0].object_id
}

# output "subnet_id" {
#   value = data.azurerm_subnet.eximus_subnet.*.name
# }
# output "clientconfig" {
#   value = data.azurerm_client_config.current
# }

# output "vnet" {
#   value = data.azurerm_virtual_network.eximus_vnet.name
# }

# output "keyv" {
#   value = data.azurerm_key_vault.eximus_KV.name
# }

# output "acrCreds" {
#   value     = azurerm_container_registry.acr.admin_password
#   sensitive = true
# }