terraform {
  backend "azurerm" {
    resource_group_name  = "xd-tf-rg"
    storage_account_name = "xdtfstorage"
    container_name       = "tfstate"
    key                  = "default.terraform.tfstate"
  }
}
