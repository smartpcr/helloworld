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
$rmContext = Get-AzureRmContext
if (!$rmContext -or $rmContext.Subscription.Name -ne $bootstrapValues.global.subscriptionName) {
    Login-AzureRmAccount
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

# create service principal (SPN)
# vGet-AzureRmADServicePrincipal | Select-Object -Property DisplayName, Id | Sort-Object -Property Id | Format-Table
$spnName = $bootstrapValues.global.servicePrincipal
$spn = Get-AzureRmADServicePrincipal | Where-Object { $_.DisplayName -eq $spnName }
if ($spn -and $spn -is [array] -and ([array]$spn).Count -ne 1) {
    throw "There are more than one service principal with the same name '$spnName'"
} 
if (!$spn) {
    Write-Host "Creating service principal with name '$spnName'"
    $certName = $spnName
    $cert = Get-AzureKeyVaultCertificate -VaultName $bootstrapValues.global.keyVault -Name $certName -ErrorAction SilentlyContinue
    if (!$cert) {
        $policy = New-AzureKeyVaultCertificatePolicy -SubjectName "CN=$spnName" -IssuerName Self -ValidityInMonths 12
        # Set-AzureRmKeyVaultAccessPolicy -VaultName $bootstrapValues.global.keyVault -UserPrincipalName ‘patti.fuller@contoso.com' -PermissionsToCertificates all
        Add-AzureKeyVaultCertificate -VaultName $bootstrapValues.global.keyVault -Name $certName -CertificatePolicy $policy
    }
    $spn = Get-OrCreateServicePrincipal -servicePrincipalName $spnName -vaultName $bootstrapValues.global.keyVault
}

Grant-ServicePrincipalPermissions `
    -servicePrincipalId $spn.Id `
    -subscriptionId $rmContext.Subscription.Id `
    -resourceGroupName $bootstrapValues.global.resourceGroup `
    -vaultName $bootstrapValues.global.keyVault

# connect as service principal
Connect-AzureRmAccount -ServicePrincipal $spnName 