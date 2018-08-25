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


$envFolder = $PSScriptRoot
if (!$envFolder) {
    $envFolder = Get-Location
}
$scriptFolder = Split-Path $envFolder -Parent
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setting service principal for environment '$EnvName'..."

$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $scriptFolder
$spnName = $bootstrapValues.global.servicePrincipal
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.global.resourceGroup
LogInfo -Message "Ensure service principal with name '$spnName' is setup for subscription '$($bootstrapValues.global.subscriptionName)'..."

# login and set subscription 
LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName


# create resource group 
$rg = Get-AzureRmResourceGroup -Name $rgName -ErrorAction SilentlyContinue
if (!$rg) {
    LogInfo -Message "Creating resource group '$rgName' in location '$($bootstrapValues.global.location)'"
    New-AzureRmResourceGroup -Name $rgName -Location $bootstrapValues.global.location
}

# create key vault 
New-AzureRmResourceGroup -Name $bootstrapValues.kv.resourceGroup -Location $bootstrapValues.kv.location
$kv = Get-AzureRmKeyVault -VaultName $vaultName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
if (!$kv) {
    LogInfo -Message "Creating Key Vault $vaultName..."
    
    New-AzureRmKeyVault -Name $vaultName `
        -ResourceGroupName $rgName `
        -Sku Standard -EnabledForDeployment -EnabledForTemplateDeployment `
        -EnabledForDiskEncryption -EnableSoftDelete `
        -Location $bootstrapValues.global.location | Out-Null
}
else {
    LogInfo -Message "Key vault $($kv.VaultName) is already created"
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