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
param([string] $envName = "dev")

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
Import-Module "$scriptFolder\common.psm1" -Force

$bootstrapValues = Get-EnvironmentSettings -envName $envName

# login and set subscription 
$rmContext = Get-AzureRmContext
if (!$rmContext -or $rmContext.Subscription.Name -ne $bootstrapValues.global.subscriptionName) {
    Login-AzureRmAccount
    Set-AzureRmContext -Subscription $bootstrapValues.global.subscriptionName
    $rmContext = Get-AzureRmContext
}

$spnName = $bootstrapValues.global.servicePrincipal
$vaultName = $bootstrapValues.global.keyVault
$rgName = $bootstrapValues.global.resourceGroup

# create resource group 
$rg = Get-AzureRmResourceGroup -Name $rgName -ErrorAction SilentlyContinue
if (!$rg) {
    Write-Host "Creating resource group '$rgName' in location '$($bootstrapValues.global.location)'"
    New-AzureRmResourceGroup -Name $rgName -Location $bootstrapValues.global.location
}

# create key vault 
$kv = Get-AzureRmKeyVault -VaultName $vaultName -ResourceGroupName $rgName -ErrorAction SilentlyContinue
if (!kv) {
    New-AzureRmKeyVault -Name $vaultName `
        -ResourceGroupName $rgName `
        -Sku Standard -EnabledForDeployment -EnabledForTemplateDeployment `
        -EnabledForDiskEncryption -EnableSoftDelete `
        -Location $bootstrapValues.global.location
}

# create service principal (SPN)
$spn = Get-AzureRmADServicePrincipal | Where-Object { $_.DisplayName -eq $spnName }
if ($spn -and $spn -is [array] -and ([array]$spn).Count -ne 1) {
    throw "There are more than one service principal with the same name '$spnName'"
} 
if (!$spn) {
    Write-Host "Creating service principal with name '$spnName'"
    $spn = Get-OrCreateServicePrincipal -servicePrincipalName $spnName -vaultName $vaultName
}

Grant-ServicePrincipalPermissions `
    -servicePrincipalId $spn.Id `
    -subscriptionId $rmContext.Subscription.Id `
    -resourceGroupName $rgName `
    -vaultName $vaultName

# connect as service principal 
Connect-ToAzure -envName $envName