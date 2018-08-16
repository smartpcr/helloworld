terraform {
  backend "azurerm" {
    resource_group_name  = "helloworld-dev4-xiaodoli-wus2-rg"
    storage_account_name = "rrdtfstate"
    container_name       = "tfstate"
    key                  = "default.terraform.tfstate"
  }
}
