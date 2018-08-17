$env:out_null = "[?n]|[0]"


function Get-OrCreatePasswordInVault2 { 
    param(
        [string] $VaultName, 
        [string] $SecretName
    )

    $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    if ($res) {
        return $res
    }

    $prng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $bytes = New-Object Byte[] 30
    $prng.GetBytes($bytes)
    $password = [System.Convert]::ToBase64String($bytes) + "!@1wW" #  ensure we meet password requirements
    az keyvault secret set --vault-name $VaultName --name $SecretName --value $password
    $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    return $res 
}

function Get-OrCreateServicePrincipalUsingPassword2 {
    param(
        [string] $ServicePrincipalName,
        [string] $ServicePrincipalPwdSecretName,
        [string] $VaultName,
        [string] $ScriptFolder,
        [string] $EnvName
    )

    $spFound =  az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    if ($spFound) {
        return $sp;
    }

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $ScriptFolder

    $rgName = $bootstrapValues.global.resourceGroup
    $azAccount = az account show | ConvertFrom-Json
    $subscriptionId = $azAccount.id
    $scopes = "/subscriptions/$subscriptionId/resourceGroups/$($rgName)"
    
    $servicePrincipalPwd = Get-OrCreatePasswordInVault2 -VaultName $VaultName -secretName $ServicePrincipalPwdSecretName
    az ad sp create-for-rbac --name $ServicePrincipalName --password $($servicePrincipalPwd.value) --role="Contributor" --scopes=$scopes 
    
    $sp = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    return $sp 
}


function LoginAzureAsUser2 {
    param (
        [string] $SubscriptionName
    )
    
    # $currentAccount = az account show | ConvertFrom-Json
    # if ($currentAccount -and $currentAccount.name -eq $SubscriptionName) {
    #     return $currentAccount
    # }

    az login
    az account set --subscription $SubscriptionName 
    $currentAccount = az account show | ConvertFrom-Json

    return $currentAccount
}

function Connect-ToAzure2 {
    param (
        [string] $EnvName = "dev",
        [string] $ScriptFolder
    )
    
    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $ScriptFolder
    $vaultName = $bootstrapValues.kv.name
    $spnName = $bootstrapValues.global.servicePrincipal
    $certName = $spnName
    $tenantId = $bootstrapValues.global.tenantId

    $privateKeyFilePath = "$ScriptFolder\credential\$certName.key"
    if (-not (Test-Path $privateKeyFilePath)) {
        az login
        az account set --subscription $bootstrapValues.global.$SubscriptionName
        DownloadCertFromKeyVault -VaultName $vaultName -CertName $certName -ScriptFolder $ScriptFolder
    }
    
    az login --service-principal -u "http://$spnName" -p $privateKeyFilePath --tenant $tenantId
}