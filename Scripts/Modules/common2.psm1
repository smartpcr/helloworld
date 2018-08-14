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

function New-OrGetServicePrincipalWithCert {
    param(
        [string] $ScriptFolder,
        [string] $EnvName
    )

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $scriptFolder
    $spnName = $bootstrapValues.global.servicePrincipal
    $vaultName = $bootstrapValues.kv.name
    $rgName = $bootstrapValues.global.resourceGroup
    $subscriptionId = $azureAccount.id 


    # create service principal (SPN) for cluster provision
    $sp = az ad sp list --display-name $spnName | ConvertFrom-Json
    if (!$sp) {
        Write-Host "Creating service principal with name '$spnName'..."

        $certName = "$spnName-cert"
        $defaultPolicyFile = "$ScriptFolder\credential\default_policy.json"
        $pfxCertFile = "$ScriptFolder\credential\$certName.pfx"
        $pemCertFile = "$ScriptFolder\credential\$certName.pem"
        $keyCertFile = "$ScriptFolder\credential\$certName.key"
        az keyvault certificate get-default-policy -o json | Out-File $defaultPolicyFile -Encoding utf8 
        az keyvault certificate create -n $certName --vault-name $kvName -p @$defaultPolicyFile
        az keyvault secret download --vault-name $kvName -n $certName -e base64 -f $pfxCertFile
        openssl pkcs12 -in $pfxCertFile -out $pemCertFile -outkey $keyCertFile -nodes
        
        New-CertificateAsSecret2 -CertName $certName -VaultName $vaultName -ScriptFolder $ScriptFolder
        $pemKeySecretName = "$($CertName)-pem"
        
        $sp = az ad sp create-for-rbac --name $spnName | ConvertFrom-Json
        az ad sp credential reset --name $spnName --cert $pemKeySecretName --keyvault $vaultName --append
        az role assignment create --assignee $sp.appId --role Contributor --scope "/subscriptions/$subscriptionId"
    
        az keyvault set-policy `
            --name $vaultName `
            --resource-group $rgName `
            --object-id $sp.objectId `
            --spn $sp.displayName `
            --certificate-permissions get list update delete `
            --secret-permissions get list set delete
    }
    else {
        Write-Host "Service principal '$spnName' already exists."
    }
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

    DownloadCertFromKeyVault -VaultName $vaultName -CertName $certName -ScriptFolder $ScriptFolder
    $privateKeyFilePath = "$ScriptFolder\credential\$certName.key"
    az login --service-principal -u "http://$spnName" -p $privateKeyFilePath --tenant $tenantId
}