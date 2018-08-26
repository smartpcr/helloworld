<#
    this script setup terraform environment
    1) load environment yaml settings from Env/${EnvName}
    2) check if client secret (password for service principal) is available, if not, login as user, create service principal and password, store password to key vault and also download it to credential folder (blocked from checkin!!!)
    3) login as service principal using password
    4) provision storage for terraform remote state 
#>
param([string] $EnvName = "dev")

$vmProvisionFolder = $PSScriptRoot
if (!$vmProvisionFolder) {
    $vmProvisionFolder = Get-Location
}
$provisionFolder = Split-Path $vmProvisionFolder -Parent
$scriptFolder = Split-Path $provisionFolder -Parent
$EnvFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "TerraformUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setup devbox VM for Environment '$EnvName'"


LogStep -Step 1 -Message "load environment yaml settings from Env/${EnvName}..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvFolder
$azAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.global.resourceGroup
$tenantId = $bootstrapValues.global.tenantId

$secretValueFile = Join-Path $EnvFolder "credential/$EnvName/azure_provider.tfvars"
if (-not (Test-Path $secretValueFile)) {
    New-Item -Path (Join-Path $EnvFolder "credential/$EnvName") -ItemType Directory -Force | Out-Null
    New-Item -Path $secretValueFile -ItemType File -Force | Out-Null
}
SetTerraformValue -valueFile $secretValueFile -name "subscription_id" -value $azAccount.id
SetTerraformValue -valueFile $secretValueFile -name "tenant_id" -value $tenantId


LogStep -Step 2 -Message "Setup Windows VM..."
$winProvisionFolder = Join-Path $vmProvisionFolder "win10"
Set-Location $winProvisionFolder
$winTfFile = Join-Path $winProvisionFolder "main.tf"
SetTerraformValue -valueFile $winTfFile -name "resource_group_name" -value $rgName
terraform init 
terraform plan -var-file $secretValueFile
terraform apply -var-file $secretValueFile


LogStep -Step 3 -Message "Setup Ubuntu VM..."
$ubuntuProvisionFolder = Join-Path $vmProvisionFolder "ubuntu1804"
Set-Location $ubuntuProvisionFolder
$ubuntuTfFile = Join-Path $ubuntuProvisionFolder "main.tf"
SetTerraformValue -valueFile $ubuntuTfFile -name "resource_group_name" -value $rgName
terraform init 
terraform plan -var-file $secretValueFile
terraform apply -var-file $secretValueFile