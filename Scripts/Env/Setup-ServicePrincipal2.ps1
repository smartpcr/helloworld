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
Write-Host "Setting up container registry for environment '$EnvName'..."

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
Import-Module "$scriptFolder\..\modules\common2.psm1" -Force
Import-Module "$scriptFolder\..\modules\YamlUtil.psm1" -Force
Import-Module "$scriptFolder\..\modules\VaultUtil.psm1" -Force

$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $scriptFolder

# login and set subscription 
$azureAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName

$spnName = $bootstrapValues.global.servicePrincipal
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.global.resourceGroup
$subscriptionId = $azureAccount.id 
$env:out_null = "[?n]|[0]"

$devValueYamlFile = "$ScriptFolder\$EnvName\values.yaml"
$values = Get-Content $devValueYamlFile -Raw | ConvertFrom-Yaml

# create resource group 
$rgGroups = az group list --query "[?name=='$rgName']" | ConvertFrom-Json
if (!$rgGroups -or $rgGroups.Count -eq 0) {
    Write-Host "Creating resource group '$rgName' in location '$($bootstrapValues.global.location)'"
    az group create --name $rgName --location $bootstrapValues.global.location 
}

# create key vault 
$kvs = az keyvault list --resource-group $rgName --query "[?name=='$vaultName']" | ConvertFrom-Json
if ($kvs.Count -eq 0) {
    Write-Host "Creating Key Vault $vaultName..."
    
    az keyvault create `
        --resource-group $rgName `
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
$sp = az ad sp list --display-name $spnName | ConvertFrom-Json
if (!$sp) {
    Write-Host "Creating service principal with name '$spnName'..."

    $certName = $spnName
    EnsureCertificateInKeyVault -VaultName $vaultName -CertName $certName -ScriptFolder $scriptFolder
    
    az ad sp create-for-rbac -n $spnName --role contributor --keyvault $vaultName --cert $certName 
    $sp = az ad sp list --display-name $spnName | ConvertFrom-Json
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


if ($bootstrapValues.global.aks -eq $true) {
    $aksSpnName = $bootstrapValues.aks.servicePrincipal
    $askSpnPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword
    $aksSpn = Get-OrCreateServicePrincipalUsingPassword2 `
        -ServicePrincipalName $aksSpnName `
        -ServicePrincipalPwdSecretName $askSpnPwdSecretName `
        -VaultName $vaultName `
        -ScriptFolder $scriptFolder `
        -EnvName $EnvName
    $aksSpn = az ad sp list --display-name $aksSpnName | ConvertFrom-Json
    
    # write to values.yaml
    $values.aksServicePrincipalAppId = $aksSpn.appId

    Grant-ServicePrincipalPermissions `
        -servicePrincipalId $aksSpn.Id `
        -subscriptionId $rmContext.Subscription.Id `
        -resourceGroupName $rgName `
        -vaultName $vaultName
}

# write to values.yaml
$values.subscriptionId = $azureAccount.id
$values.servicePrincipalAppId = $sp.appId
$values.tenantId = $azureAccount.tenantId  
$values | ConvertTo-Yaml | Out-File $devValueYamlFile -Encoding utf8

# connect as service principal 
Connect-ToAzure2 -EnvName $EnvName -ScriptFolder $scriptFolder