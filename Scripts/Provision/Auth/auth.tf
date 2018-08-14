data "external" "vault" {
    program = ["PowerShell.exe", "../utils/Get-ValueFromKeyVault.ps1"]

    query {
        ServicePrincipalAppId = "ff820867-4de8-4f98-9c39-6d339c30927d"
        VaultName = "hw-dev3-xiaodoli-kv"
        TenantId = "f7215caf-efd9-4bac-89c5-a3cf109a9f18"
        CertThumbprint = "BB55547547C2689A079B11A94914AA87046A57F9"
        Name = "helloworld-dev3-xiaodoli-k8s-webapp-pwd"
    }
}

output "secret" {
  value = "${data.external.vault.result.app_secret}"
}
