
param(
    [string] $ServicePrincipalAppId,
    [string] $CertThumbprint,
    [string] $TenantId,
    [string] $VaultName,
    [string] $Name,
    [string] $Value 
)

Login-AzureRmAccount `
    -TenantId $TenantId `
    -ServicePrincipal `
    -CertificateThumbprint $CertThumbprint `
    -ApplicationId $ServicePrincipalAppId

Set-AzureKeyVaultSecret -VaultName $VaultName -Name $Name -SecretValue ($Value | ConvertTo-SecureString -AsPlainText -Force)
