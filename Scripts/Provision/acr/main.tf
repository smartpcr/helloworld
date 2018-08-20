provider "azurerm" {
  client_id = "${var.client_id}"
  client_secret = "${var.client_secret}"
  tenant_id = "${var.tenant_id}"
  subscription_id = "${var.subscription_id}"
}

resource "azurerm_container_registry" "acr" {
  name                = "${var.acr_name}"
  resource_group_name = "${var.acr_resource_group_name}"
  location            = "${var.location}"
  admin_enabled       = false
  sku                 = "${var.acr_sku}"
  tags                = "${var.tags}"
}
