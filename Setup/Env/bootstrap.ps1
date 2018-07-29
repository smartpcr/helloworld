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

Install-Module powershell-yaml
Import-Module "$scriptFolder\common.psm1" -Force

$values = Get-Content "$scriptFolder\values.yaml" -Raw | ConvertFrom-Yaml
if ($envName) {
    $envValueYamlFile = "$scriptFolder\$envName\values.yaml"
    if (Test-Path $envValueYamlFile) {
        $envValues = Get-Content $envValueYamlFile -Raw | ConvertFrom-Yaml
        Copy-YamlObject -fromObj $envValues -toObj $values
    }
}

$bootstrapTemplate = Get-Content "$scriptFolder\bootstrap.yaml" -Raw
$bootstrapTemplate = Set-Values -valueTemplate $bootstrapTemplate -settings $values
$bootstrapValues = $bootstrapTemplate | ConvertFrom-Yaml

# login and set subscription 
Connect-AzureRmAccount
$rmContext = Get-AzureRmContext
if (!$rmContext -or $rmContext.Subscription.Name -ne $bootstrapValues.global.subscriptionName) {
    Set-AzureRmContext -Subscription $bootstrapValues.global.subscriptionName
    $rmContext = Get-AzureRmContext
}

# create resource group 
$rg = Get-AzureRmResourceGroup -Name $bootstrapValues.global.resourceGroup -ErrorAction SilentlyContinue
if (!$rg) {
    New-AzureRmResourceGroup -Name $bootstrapValues.global.resourceGroup -Location $bootstrapValues.global.location
}

# create key vault 
$kv = Get-AzureRmKeyVault -VaultName $bootstrapValues.global.keyVault -ResourceGroupName $bootstrapValues.global.resourceGroup -ErrorAction SilentlyContinue
if (!kv) {
    New-AzureRmKeyVault -Name $bootstrapValues.global.keyVault `
        -ResourceGroupName $bootstrapValues.global.resourceGroup `
        -Sku Standard -EnabledForDeployment -EnabledForTemplateDeployment `
        -EnabledForDiskEncryption -EnableSoftDelete `
        -Location $bootstrapValues.global.location
}