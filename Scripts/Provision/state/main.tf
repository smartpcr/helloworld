terraform {
  backend "azurerm" {
      resource_group_name = "${var.resource_group_name}"
    storage_account_name = "lingxd_rrd_ultimate"
    container_name       = "tfstate"
    key                  = "default.terraform.tfstate"
  }
}
