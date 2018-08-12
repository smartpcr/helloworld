data "azurerm_key_vault_secret" "bootstrap" {
    name = "service_principal_app_id"
    vault_uri = "https://xiaodonglab.vault.azure.net"
}

output "service_principal_app_id" {
    value = "${data.azurerm_key_vault_secret.bootstrap.value}"
}