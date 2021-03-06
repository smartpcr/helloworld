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
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder
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


LogStep -Step 5 -Message "Ensure aks service principal has access to ACR..."
$acrName = $bootstrapValues.acr.name
$acrResourceGroup = $bootstrapValues.acr.resourceGroup
$acrFound = "$(az acr list -g $acrResourceGroup --query ""[?contains(name, '$acrName')]"" --query [].name -o tsv)"
if (!$acrFound) {
    throw "Please setup ACR first by running Setup-ContainerRegistry.ps1 script"
}
$acrId = "$(az acr show --name $acrName --query id --output tsv)"
$aksSpnName = $bootstrapValues.aks.servicePrincipal
$aksSpn = az ad sp list --display-name $aksSpnName | ConvertFrom-Json
az role assignment create --assignee $aksSpn.appId --scope $acrId --role contributor | Out-Null



LogStep -Step 6 -Message "Run terraform provision..." 
Set-Location $aksProvisionFolder
terraform init 
terraform plan -var-file $credentialTfFile
terraform apply -var-file $credentialTfFile
# terraform destroy -var-file $credentialTfFile


LogStep -Step 7 -Message "View kubenetes dashboard..." 
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName
$kubeContextName = "$(kubectl config current-context)"
LogInfo -Message "You are now connected to kubenetes context: '$kubeContextName'" 
# run the following on windows
# Start-Process powershell.exe "az aks browse --resource-group $($bootstrapValues.aks.resourceGroup) --name $($bootstrapValues.aks.clusterName)"
# run the following on mac
# az aks browse --resource-group $($bootstrapValues.aks.resourceGroup) --name $($bootstrapValues.aks.clusterName) &


LogStep -Step 8 -Message "Setup helm integration, install cert manager..."
kubectl -n kube-system create sa tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller --upgrade



