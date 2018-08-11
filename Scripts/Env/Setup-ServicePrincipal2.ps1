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

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
Import-Module "$scriptFolder\..\modules\common.psm1" -Force
Import-Module "$scriptFolder\..\modules\common2.psm1" -Force
Import-Module "$scriptFolder\..\modules\CertUtil.psm1" -Force

$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $scriptFolder

# login and set subscription 
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName

$spnName = $bootstrapValues.global.servicePrincipal
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.global.resourceGroup

# create resource group 
$rg = az group show --name $rgName | ConvertFrom-Json
if (!$rg) {
    Write-Host "Creating resource group '$rgName' in location '$($bootstrapValues.global.location)'"
    az group create --name $rgName --location $bootstrapValues.global.location
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
        --query "[?n]|[0]"
}
else {
    Write-Host "Key vault $($kv.VaultName) is already created"
}

# create service principal (SPN) for cluster provision
$spn = Get-OrCreateServicePrincipalUsingCert -ServicePrincipalName $spnName -VaultName $vaultName -ScriptFolder $scriptFolder -EnvName $EnvName 

Grant-ServicePrincipalPermissions `
    -servicePrincipalId $spn.Id `
    -subscriptionId $rmContext.Subscription.Id `
    -resourceGroupName $rgName `
    -vaultName $vaultName

if ($bootstrapValues.global.aks -eq $true) {
    $aksSpnName = $bootstrapValues.aks.servicePrincipal
    $askSpnPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword
    $aksSpn = Get-OrCreateServicePrincipalUsingPassword -ServicePrincipalName $aksSpnName -ServicePrincipalPwdSecretName $askSpnPwdSecretName -VaultName $vaultName -ScriptFolder $scriptFolder -EnvName $EnvName
    
    # write to values.yaml
    $devValueYamlFile = "$ScriptFolder\$EnvName\values.yaml"
    $values = Get-Content $devValueYamlFile -Raw | ConvertFrom-Yaml
    $values.aksServicePrincipalAppId = $aksSpn.ApplicationId
    $values | ConvertTo-Yaml | Out-File $devValueYamlFile -Encoding utf8


    Grant-ServicePrincipalPermissions `
        -servicePrincipalId $aksSpn.Id `
        -subscriptionId $rmContext.Subscription.Id `
        -resourceGroupName $rgName `
        -vaultName $vaultName
}


# connect as service principal 
Connect-ToAzure -EnvName $EnvName -ScriptFolder $scriptFolder