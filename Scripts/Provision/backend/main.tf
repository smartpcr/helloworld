terraform {
  backend "azurerm" {
    resource_group_name  = "tf-xiaodoli-rg"
    storage_account_name = "tfstoragexiaodoli"
    container_name       = "tfstate"
    key                  = "default.terraform.tfstate"
  }
}
