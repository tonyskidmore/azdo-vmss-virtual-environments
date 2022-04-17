output "resource_group" {
  value = azurerm_resource_group.rg
}
output "azurerm_client_config" {
  value = data.azurerm_client_config.current
}
