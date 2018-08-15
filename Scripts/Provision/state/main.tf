terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate"
    storage_account_name = "rrdtfstate"
    container_name       = "tfstate"
    key                  = "default.terraform.tfstate"
    access_key           = "ZHVtbXk="
  }
}
