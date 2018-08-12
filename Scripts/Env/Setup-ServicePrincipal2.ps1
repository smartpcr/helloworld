<#
    this script retrieve settings based on target environment
    1) create azure resource group
    2) create key vault
    3) create certificate and add to key vault
    4) create service principle with cert auth
    5) grant permission to service principle
        a) key vault
        b) resource group
#>
param([string] $EnvName = "mac")

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
Import-Module "$scriptFolder\..\modules\common2.psm1" -Force
Import-Module "$scriptFolder\..\modules\YamlUtil.psm1" -Force

$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $scriptFolder

# login and set subscription 
$azureAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName

$spnName = $bootstrapValues.global.servicePrincipal
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.global.resourceGroup
$subscriptionId = $azureAccount.id 
$env:out_null = "[?n]|[0]"

# create resource group 
$rg = az group show --name $rgName | ConvertFrom-Json
if (!$rg) {
    Write-Host "Creating resource group '$rgName' in location '$($bootstrapValues.global.location)'"
    az group create --name $rgName --location $bootstrapValues.global.location --query $env:out_null
}

# create key vault 
$kv = az keyvault show --name $vaultName --resource-group $rgName | ConvertFrom-Json
if (!$kv) {
    Write-Host "Creating Key Vault $vaultName..."
    
    az keyvault create `
        --resource-group $rgName `
        --name $vaultName `
        --sku standard `
        --location $bootstrapValues.global.location `
        --enabled-for-deployment $true `
        --enabled-for-disk-encryption $true `
        --enabled-for-template-deployment $true `
        --query $env:out_null
}
else {
    Write-Host "Key vault $($kv.VaultName) is already created"
}

# create service principal (SPN) for cluster provision
$sp = az ad sp list --display-name $spnName | ConvertFrom-Json
if (!$sp) {
    Write-Host "Creating service principal with name '$spnName'..."

    $certName = $spnName
    az ad sp create-for-rbac --name $spnName --create-cert --cert $certName --keyvault $vaultName 
    az role assignment create --assignee $sp.appId --role Contributor --scope "/subscriptions/$subscriptionId"

    
    az keyvault set-policy `
        --name $vaultName `
        --resource-group $rgName `
        --object-id $sp.objectId `
        --spn $sp.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete
}

$devValueYamlFile = "$ScriptFolder\$EnvName\values.yaml"
$values = Get-Content $devValueYamlFile -Raw | ConvertFrom-Yaml
$values.subscriptionId = $azureAccount.id
$values.servicePrincipalAppId = $sp.appId
$values.tenantId = $sp.tenantId  
$values | ConvertTo-Yaml | Out-File $devValueYamlFile -Encoding utf8

# connect as service principal 
Connect-ToAzure2 -EnvName $EnvName -ScriptFolder $scriptFolder