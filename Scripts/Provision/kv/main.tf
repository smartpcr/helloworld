provider "azurerm" {
  subscription_id = "${var.subscription_id}"
  client_id       = "${var.client_id}"
  client_secret   = "${var.client_secret}"
  tenant_id       = "${var.tenant_id}"
  alias           = "arm"
}

resource "azurerm_resource_group" "rg" {
  name     = "${var.resource_group_name}"
  location = "west us 2"
  provider = "azurerm.arm"
}

resource "azurerm_key_vault" "kv" {
  name                = "${var.vault_name}"
  resource_group_name = "${var.resource_group_name}"
}
