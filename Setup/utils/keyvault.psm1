function Get-Secret {
    param(
        [string] $VaultName,
        [string] $Name 
    )

    $secret = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $Name
    return $secret.SecretValueText 
}

function Set-Secret {
    
}