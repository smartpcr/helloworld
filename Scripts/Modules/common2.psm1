$env:out_null = "[?n]|[0]"

function LoginAzureAsUser2 {
    param (
        [string] $SubscriptionName
    )
    
    $currentAccount = az account show | ConvertFrom-Json
    if ($currentAccount -and $currentAccount.name -eq $SubscriptionName) {
        return $currentAccount
    }

    az login --query $env:out_null
    az account set --subscription $SubscriptionName --query $env:out_null
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

    az keyvault certificate download --vault-name $vaultName --name $certName --encoding PEM --file "$certName.pem"
    # openssl x509 -in "$certName.pem" -inform PEM  -noout -sha1 -fingerprint

    az login --service-principal -u "http://$spnName" -p "$certName.pem" --tenant $tenantId
}