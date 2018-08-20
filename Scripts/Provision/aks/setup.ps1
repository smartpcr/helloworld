param([string] $EnvName = "dev")

$ErrorActionPreference = "Stop"
Write-Host "Setting up container registry for environment '$EnvName'..."

$aksProvisionFolder = $PSScriptRoot
if (!$aksProvisionFolder) {
    $aksProvisionFolder = Get-Location
}
$scriptFolder = "$aksProvisionFolder/../.." 
Import-Module "$scriptFolder/modules/YamlUtil.psm1" -Force
Import-Module "$scriptFolder/modules/common2.psm1" -Force
Import-Module "$scriptFolder/modules/CertUtil.psm1" -Force
Import-Module "$scriptFolder/modules/VaultUtil.psm1" -Force
Import-Module "$scriptFolder/modules/TerraformUtil.psm1" -Force
$envFolder = Join-Path $scriptFolder "Env"


Write-Host "1) Retrieving settings for environment '$EnvName'..." -ForegroundColor Green
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -ScriptFolder $envFolder
$akstfvarFile = Join-Path $aksProvisionFolder "terraform.tfvars"
$credentialFolder = Join-Path $envFolder "credential"
$envCredentialFolder = Join-Path $credentialFolder $EnvName
$credentialTfFile = Join-Path $envCredentialFolder "aks.tfvars"
SetTerraformValue -valueFile $akstfvarFile -name "resource_group_name" -value $bootstrapValues.global.resourceGroup
SetTerraformValue -valueFile $akstfvarFile -name "location" -value $bootstrapValues.global.location
SetTerraformValue -valueFile $akstfvarFile -name "aks_resource_group_name" -value $bootstrapValues.global.resourceGroup
SetTerraformValue -valueFile $akstfvarFile -name "aks_name" -value $bootstrapValues.aks.clusterName
SetTerraformValue -valueFile $akstfvarFile -name "acr_name" -value $bootstrapValues.acr.name
SetTerraformValue -valueFile $akstfvarFile -name "dns_prefix" -value $bootstrapValues.aks.dnsPrefix


Write-Host "2) Login as terraform service principal..." -ForegroundColor Green
$spnPwdSecretName = $bootstrapValues.terraform.servicePrincipalSecretName
$tfSpPwd = Get-OrCreatePasswordInVault2 -VaultName $bootstrapValues.kv.name -SecretName $spnPwdSecretName
az login --service-principal -u "http://$($bootstrapValues.terraform.servicePrincipal)" -p $tfSpPwd.value --tenant $bootstrapValues.global.tenantId
$tfsp = az ad sp list --display-name $bootstrapValues.terraform.servicePrincipal | ConvertFrom-Json


Write-Host "3) Retrieve aks service principal..." -ForegroundColor Green
$servicePrincipalPwd = az keyvault secret show `
    --vault-name $bootstrapValues.kv.name `
    --name $bootstrapValues.aks.servicePrincipalPassword | ConvertFrom-Json

$azAccount = az account show | ConvertFrom-Json
SetTerraformValue -valueFile $credentialTfFile -name "subscription_id" -value $azAccount.id 
SetTerraformValue -valueFile $credentialTfFile -name "tenant_id" -value $azAccount.tenantId
SetTerraformValue -valueFile $credentialTfFile -name "client_id" -value $tfsp.appId
SetTerraformValue -valueFile $credentialTfFile -name "client_secret" -value $servicePrincipalPwd.value   
SetTerraformValue -valueFile $akstfvarFile -name "aks_service_principal_app_id" -value $bootstrapValues.aks.servicePrincipalAppId
SetTerraformValue -valueFile $credentialTfFile -name "aks_service_principal_password" -value $servicePrincipalPwd.value 


Write-Host "4) Ensure linux ssh key is available..." -ForegroundColor Green
EnsureSshCert `
    -VaultName $bootstrapValues.kv.name `
    -CertName $bootstrapValues.aks.ssh_private_key `
    -EnvName $EnvName `
    -ScriptFolder $scriptFolder
$aksCertPublicKeyFile = Join-Path $envCredentialFolder $bootstrapValues.aks.ssh_pubblic_key

SetTerraformValue -valueFile $credentialTfFile -name "aks_ssh_public_key" -value $aksCertPublicKeyFile 

Write-Host "5) Run terraform provision..." -ForegroundColor Green
terraform init 
terraform plan -var-file $credentialTfFile
terraform apply -var-file $credentialTfFile
# terraform destroy -var-file $credentialTfFile