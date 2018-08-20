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
param([string] $EnvName = "dev")

$ErrorActionPreference = "Stop"
Write-Host "Setting up container registry for environment '$EnvName'..." -ForegroundColor Green

$envFolder = $PSScriptRoot
if (!$envFolder) {
    $envFolder = Get-Location
}
$scriptFolder = Join-Path $envFolder "../"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force

$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $envFolder

# login and set subscription 
Write-Host "1) Login to azure and set subscription to '$($bootstrapValues.global.subscriptionName)'..." -ForegroundColor Green
$azureAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName

$spnName = $bootstrapValues.global.servicePrincipal
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.global.resourceGroup
$subscriptionId = $azureAccount.id 
$env:out_null = "[?n]|[0]"

$devValueYamlFile = "$envFolder\$EnvName\values.yaml"
$values = Get-Content $devValueYamlFile -Raw | ConvertFrom-Yaml

# create resource group 
Write-Host "2) Creating resource group '$($rgName)' at location '$($bootstrapValues.global.location)'..." -ForegroundColor Green
$rgGroups = az group list --query "[?name=='$rgName']" | ConvertFrom-Json
if (!$rgGroups -or $rgGroups.Count -eq 0) {
    Write-Host "Creating resource group '$rgName' in location '$($bootstrapValues.global.location)'"
    az group create --name $rgName --location $bootstrapValues.global.location | Out-Null
}

# create key vault 
Write-Host "3) Creating key vault '$vaultName' within resource group '$($bootstrapValues.kv.resourceGroup)' at location '$($bootstrapValues.kv.location)'..." -ForegroundColor Green
$kvrg = az group list --query "[?name=='$($bootstrapValues.kv.resourceGroup)']" | ConvertFrom-Json
if (!$kvrg) {
    az group create --name $bootstrapValues.kv.resourceGroup --location $bootstrapValues.kv.location | Out-Null
}
$kvs = az keyvault list --resource-group $bootstrapValues.kv.resourceGroup --query "[?name=='$vaultName']" | ConvertFrom-Json
if ($kvs.Count -eq 0) {
    Write-Host "Creating Key Vault $vaultName..."
    
    az keyvault create `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --name $vaultName `
        --sku standard `
        --location $bootstrapValues.global.location `
        --enabled-for-deployment $true `
        --enabled-for-disk-encryption $true `
        --enabled-for-template-deployment $true 
}
else {
    Write-Host "Key vault $($vaultName) is already created"
}

# create service principal (SPN) for cluster provision
Write-Host "4) Creating service principal '$($spnName)'..." -ForegroundColor Green
$sp = az ad sp list --display-name $spnName | ConvertFrom-Json
if (!$sp) {
    Write-Host "Creating service principal with name '$spnName'..."

    $certName = $spnName
    EnsureCertificateInKeyVault -VaultName $vaultName -CertName $certName -ScriptFolder $envFolder
    
    az ad sp create-for-rbac -n $spnName --role contributor --keyvault $vaultName --cert $certName 
    $sp = az ad sp list --display-name $spnName | ConvertFrom-Json
    az role assignment create --assignee $sp.appId --role Contributor --scope "/subscriptions/$subscriptionId"

    az keyvault set-policy `
        --name $vaultName `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --object-id $sp.objectId `
        --spn $sp.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete
}
else {
    Write-Host "Service principal '$spnName' already exists."
}


if ($bootstrapValues.global.aks -eq $true) {
    Write-Host "5) Creating AKS service principal '$($bootstrapValues.aks.servicePrincipal)'..." -ForegroundColor Green
    $aksrg = az group list --query "[?name=='$($bootstrapValues.aks.resourceGroup)']" | ConvertFrom-Json
    if (!$aksrg) {
        az group create --name $bootstrapValues.aks.resourceGroup --location $bootstrapValues.aks.location | Out-Null
    }

    $aksSpnName = $bootstrapValues.aks.servicePrincipal
    $askSpnPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword
    $aksSpn = Get-OrCreateServicePrincipalUsingPassword2 `
        -ServicePrincipalName $aksSpnName `
        -ServicePrincipalPwdSecretName $askSpnPwdSecretName `
        -VaultName $vaultName `
        -ScriptFolder $envFolder `
        -EnvName $EnvName
    
    $aksSpn = az ad sp list --display-name $aksSpnName | ConvertFrom-Json
    
    # write to values.yaml
    $values.aksServicePrincipalAppId = $aksSpn.appId

    az role assignment create --assignee $aksSpn.appId --role Contributor --resource-group $bootstrapValues.aks.resourceGroup
    az keyvault set-policy `
        --name $vaultName `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --object-id $aksSpn.objectId `
        --spn $aksSpn.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete
}

# write to values.yaml
$values.subscriptionId = $azureAccount.id
$values.servicePrincipalAppId = $sp.appId
$values.tenantId = $azureAccount.tenantId  
$values | ConvertTo-Yaml | Out-File $devValueYamlFile -Encoding utf8

# connect as service principal 
LoginAsServicePrincipal -EnvName $EnvName -ScriptFolder $envFolder