param([string] $EnvName = "dev")

$aksProvisionFolder = $PSScriptRoot
if (!$aksProvisionFolder) {
    $aksProvisionFolder = Get-Location
}
$scriptFolder = Split-Path (Split-Path $aksProvisionFolder -Parent) -Parent
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "TerraformUtil.psm1") -Force
$envFolder = Join-Path $scriptFolder "Env"
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setup AKS Cluster for Environment '$EnvName'"

LogStep -Step 1 -Message "Retrieving settings for environment '$EnvName'..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -ScriptFolder $envFolder
$akstfvarFile = Join-Path $aksProvisionFolder "terraform.tfvars"
$credentialFolder = Join-Path $envFolder "credential"
$envCredentialFolder = Join-Path $credentialFolder $EnvName
$credentialTfFile = Join-Path $envCredentialFolder "aks.tfvars"
SetTerraformValue -valueFile $akstfvarFile -name "resource_group_name" -value $bootstrapValues.global.resourceGroup
SetTerraformValue -valueFile $akstfvarFile -name "location" -value $bootstrapValues.aks.location
SetTerraformValue -valueFile $akstfvarFile -name "aks_resource_group_name" -value $bootstrapValues.aks.resourceGroup
SetTerraformValue -valueFile $akstfvarFile -name "aks_name" -value $bootstrapValues.aks.clusterName
SetTerraformValue -valueFile $akstfvarFile -name "acr_name" -value $bootstrapValues.acr.name
SetTerraformValue -valueFile $akstfvarFile -name "dns_prefix" -value $bootstrapValues.aks.dnsPrefix


LogStep -Step 2 -Message "Login as terraform service principal..."
$tfsp = az ad sp list --display-name $bootstrapValues.terraform.servicePrincipal | ConvertFrom-Json
if (!$tfsp) {
    throw "Terraform is not setup yet. Please run Setup-TerraformAccess.ps1 first"
}
$spnPwdSecretName = $bootstrapValues.terraform.servicePrincipalSecretName
$tfSpPwd = Get-OrCreatePasswordInVault2 -VaultName $bootstrapValues.kv.name -SecretName $spnPwdSecretName
# az login --service-principal -u "http://$($bootstrapValues.terraform.servicePrincipal)" -p $tfSpPwd.value --tenant $bootstrapValues.global.tenantId


LogStep -Step 3 -Message "Retrieve aks service principal..." 
$servicePrincipalPwd = az keyvault secret show `
    --vault-name $bootstrapValues.kv.name `
    --name $bootstrapValues.aks.servicePrincipalPassword | ConvertFrom-Json

$azAccount = az account show | ConvertFrom-Json
SetTerraformValue -valueFile $credentialTfFile -name "subscription_id" -value $azAccount.id 
SetTerraformValue -valueFile $credentialTfFile -name "tenant_id" -value $azAccount.tenantId
SetTerraformValue -valueFile $credentialTfFile -name "client_id" -value $tfsp.appId
SetTerraformValue -valueFile $credentialTfFile -name "client_secret" -value $tfSpPwd.value   
SetTerraformValue -valueFile $credentialTfFile -name "aks_service_principal_password" -value $servicePrincipalPwd.value 

SetTerraformValue -valueFile $akstfvarFile -name "aks_service_principal_app_id" -value $bootstrapValues.aks.servicePrincipalAppId
SetTerraformValue -valueFile $akstfvarFile -name "aks_resource_group_name" -value $bootstrapValues.aks.resourceGroup
SetTerraformValue -valueFile $akstfvarFile -name "acr_resource_group_name" -value $bootstrapValues.acr.resourceGroup


LogStep -Step 4 -Message "Ensure linux ssh key is available..." 
EnsureSshCert `
    -VaultName $bootstrapValues.kv.name `
    -CertName $bootstrapValues.aks.ssh_private_key `
    -EnvName $EnvName `
    -ScriptFolder $scriptFolder
$aksCertPublicKeyFile = Join-Path $envCredentialFolder "$($bootstrapValues.aks.ssh_private_key).pub"
SetTerraformValue -valueFile $akstfvarFile -name "aks_ssh_public_key" -value $aksCertPublicKeyFile 


LogStep -Step 5 -Message "Run terraform provision..." 
terraform init 
terraform plan -var-file $credentialTfFile
terraform apply -var-file $credentialTfFile
# terraform destroy -var-file $credentialTfFile

LogStep -Step 6 -Message "View kubenetes dashboard..." 
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName
az aks browse --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName