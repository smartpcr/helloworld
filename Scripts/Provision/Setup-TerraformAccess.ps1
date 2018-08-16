<#
    this script setup terraform environment
    1) load environment yaml settings from Env/${EnvName}
    2) check if client secret (password for service principal) is available, if not, login as user, create service principal and password, store password to key vault and also download it to credential folder (blocked from checkin!!!)
    3) login as service principal using password
    4) provision storage for terraform remote state 
#>
param([string] $EnvName = "dev")

$ErrorActionPreference = "Stop"
Write-Host "Setting up container registry for environment '$EnvName'..." -ForegroundColor Green 

$provisionFolder = $PSScriptRoot
if (!$provisionFolder) {
    $provisionFolder = Get-Location
}
$EnvFolder = "$provisionFolder/../Env"
Import-Module "$provisionFolder\..\modules\common2.psm1" -Force
Import-Module "$provisionFolder\..\modules\YamlUtil.psm1" -Force
Import-Module "$provisionFolder\..\modules\VaultUtil.psm1" -Force
Import-Module "$provisionFolder\..\modules\TerraformUtil.psm1" -Force

Write-Host "1) load environment yaml settings from Env/${EnvName}..." -ForegroundColor Green
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $EnvFolder
$spnName = $bootstrapValues.terraform.servicePrincipal
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.global.resourceGroup
$tenantId = $bootstrapValues.global.tenantId
$spnPwdSecretName = $bootstrapValues.terraform.servicePrincipalSecretName

$secretValueFile = Join-Path $EnvFolder "credential/$EnvName/azure_provider.tfvars"
if (-not (Test-Path $secretValueFile)) {
    New-Item -Path (Join-Path $EnvFolder "credential/$EnvName") -ItemType Directory -Force | Out-Null
    "" | Out-File $secretValueFile
}
SetTerraformValue -valueFile $secretValueFile -name "tenant_id" -value $tenantId
$stateValueFile = Join-Path $provisionFolder "state/terraform.tfvars"
SetTerraformValue -valueFile $stateValueFile -name "resource_group_name" -value $rgName

Write-Host "2) Ensure service principal is created with password stored in key vault" -ForegroundColor Green
az login 
az account set --subscription $bootstrapValues.global.subscriptionName
$azAccount = az account show | ConvertFrom-Json
$subscriptionId = $azAccount.id
$tfSp = az ad sp list --display-name $spnName | ConvertFrom-Json
$tfSpPwd = Get-OrCreatePasswordInVault2 -VaultName $vaultName -SecretName $spnPwdSecretName
if (!$tfSp) {
    az ad sp create-for-rbac -n $spnName --role contributor --password $tfSpPwd.value 
    $tfSp = az ad sp list --display-name $spnName | ConvertFrom-Json
    az role assignment create --assignee $tfSp.appId --role Contributor --scope "/subscriptions/$subscriptionId"
}

SetTerraformValue -valueFile $secretValueFile -name "subscription_id" -value $subscriptionId
SetTerraformValue -valueFile $secretValueFile -name "client_id" -value $tfSp.appId
SetTerraformValue -valueFile $secretValueFile -name "client_secret" -value $tfSpPwd.value

Write-Host "3) Login as service principal '$spnName'" -ForegroundColor Green
az login --service-principal -u "http://$spnName" -p $tfSpPwd.value --tenant $tenantId

Write-Host "4) Provisioning storage account..." -ForegroundColor Green
$tfStorageAccountName = $bootstrapValues.terraform.storageAccountName
$tfBlobContainerName = $bootstrapValues.terraform.blobContainerName
$tfStorageAcct = az storage account show --resource-group $rgName --name $tfStorageAccountName | ConvertFrom-Json
if (!$tfStorageAcct) {
    az storage account create --resource-group $rgName --name $tfStorageAccountName
    $tfStorageAcct = az storage account show --resource-group $rgName --name $tfStorageAccountName | ConvertFrom-Json
    $storageKeys = az storage account keys list --resource-group $rgName --account-name $tfStorageAccountName | ConvertFrom-Json
    az storage container create --name $tfBlobContainerName --account-name $tfStorageAccountName --account-key $storageKeys[0].value
}
$tfStorageAccessKey = $(az storage account keys list --resource-group $rgName --account-name $tfStorageAccountName | ConvertFrom-Json)[0].value 
$stateFile = Join-Path $provisionFolder "state/main.tf"
SetTerraformValue -valueFile $stateFile -name "storage_account_name" -value $tfStorageAccountName
SetTerraformValue -valueFile $stateFile -name "container_name" -value $tfBlobContainerName
SetTerraformValue -valueFile $stateFile -name "resource_group_name" -value $rgName
SetTerraformValue -valueFile $secretValueFile -name "access_key" -value $tfStorageAccessKey

Set-Location "$provisionFolder/state"
terraform init -upgrade -backend-config="access_key=$tfStorageAccessKey"
terraform plan -var-file $secretValueFile
terraform apply -var-file $secretValueFile