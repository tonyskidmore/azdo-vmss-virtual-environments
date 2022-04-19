data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_management_lock" "rg" {
  name       = "rg-lock"
  scope      = azurerm_resource_group.rg.id
  lock_level = "CanNotDelete"
  notes      = "Locked for compliance"
}
