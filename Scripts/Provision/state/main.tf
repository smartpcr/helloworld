terraform {
  backend "azurerm" {
    storage_account_name = "lingxd_rrd_ultimate"
    container_name       = "tfstate"
    key                  = "default.terraform.tfstate"
  }
}
