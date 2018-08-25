param([string] $EnvName = "dev")

$ErrorActionPreference = "Stop"
Write-Host "Setting up container registry for environment '$EnvName'..."

$acrProvisionFolder = $PSScriptRoot
if (!$acrProvisionFolder) {
    $acrProvisionFolder = Get-Location
}
$scriptFolder = Split-Path (Split-Path $acrProvisionFolder -Parent) -Parent
Import-Module "$scriptFolder/modules/YamlUtil.psm1" -Force
Import-Module "$scriptFolder/modules/common2.psm1" -Force
Import-Module "$scriptFolder/modules/CertUtil.psm1" -Force
Import-Module "$scriptFolder/modules/VaultUtil.psm1" -Force
Import-Module "$scriptFolder/modules/TerraformUtil.psm1" -Force
$envFolder = Join-Path $scriptFolder "Env"


Write-Host "1) Retrieving settings for environment '$EnvName'..." -ForegroundColor Green
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder
$credentialFolder = Join-Path $envFolder "credential"
if (-not (Test-Path $credentialFolder)) {
    New-Item -Path $credentialFolder -ItemType Directory -Force | Out-Null
}
$envCredentialFolder = Join-Path $credentialFolder $EnvName
if (-not (Test-Path $envCredentialFolder)) {
    New-Item -Path $envCredentialFolder -ItemType Directory -Force | Out-Null
}
$credentialTfFile = Join-Path $envCredentialFolder "acr.tfvars"
$acrtfvarFile = Join-Path $acrProvisionFolder "terraform.tfvars"
SetTerraformValue -valueFile $acrtfvarFile -name "resource_group_name" -value $bootstrapValues.global.resourceGroup
SetTerraformValue -valueFile $acrtfvarFile -name "location" -value $bootstrapValues.global.location
SetTerraformValue -valueFile $acrtfvarFile -name "acr_name" -value $bootstrapValues.acr.name


Write-Host "1) Retrieving settings for environment '$EnvName'..." -ForegroundColor Green
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder
$credentialFolder = Join-Path $envFolder "credential"
$envCredentialFolder = Join-Path $credentialFolder $EnvName
$credentialTfFile = Join-Path $envCredentialFolder "acr.tfvars"
$acrtfvarFile = Join-Path $acrProvisionFolder "terraform.tfvars"
SetTerraformValue -valueFile $acrtfvarFile -name "resource_group_name" -value $bootstrapValues.global.resourceGroup
SetTerraformValue -valueFile $acrtfvarFile -name "location" -value $bootstrapValues.global.location
SetTerraformValue -valueFile $acrtfvarFile -name "acr_name" -value $bootstrapValues.acr.name
SetTerraformValue -valueFile $acrtfvarFile -name "acr_resource_group_name" -value $bootstrapValues.acr.resourceGroup


Write-Host "2) Login as terraform service principal..." -ForegroundColor Green
$azAccount = az account show | ConvertFrom-Json
$tfsp = az ad sp list --display-name $bootstrapValues.terraform.servicePrincipal | ConvertFrom-Json
$spnPwdSecretName = $bootstrapValues.terraform.servicePrincipalSecretName
$tfSpPwd = Get-OrCreatePasswordInVault2 -VaultName $bootstrapValues.kv.name -SecretName $spnPwdSecretName
# az login --service-principal -u "http://$($bootstrapValues.terraform.servicePrincipal)" -p $tfSpPwd.value --tenant $bootstrapValues.global.tenantId
SetTerraformValue -valueFile $credentialTfFile -name "subscription_id" -value $azAccount.id 
SetTerraformValue -valueFile $credentialTfFile -name "tenant_id" -value $azAccount.tenantId
SetTerraformValue -valueFile $credentialTfFile -name "client_id" -value $tfsp.appId
SetTerraformValue -valueFile $credentialTfFile -name "client_secret" -value $tfSpPwd.value   


Write-Host "3) Run terraform provision..." -ForegroundColor Green
terraform init 
terraform plan -var-file $credentialTfFile
terraform apply -var-file $credentialTfFile
# terraform destroy -var-file $credentialTfFile