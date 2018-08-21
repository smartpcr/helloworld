<#
    this script setup terraform environment
    1) load environment yaml settings from Env/${EnvName}
    2) check if client secret (password for service principal) is available, if not, login as user, create service principal and password, store password to key vault and also download it to credential folder (blocked from checkin!!!)
    3) login as service principal using password
    4) provision storage for terraform remote state 
#>
param([string] $EnvName = "dev")

$provisionFolder = $PSScriptRoot
if (!$provisionFolder) {
    $provisionFolder = Get-Location
}
$scriptFolder = Split-Path $provisionFolder -Parent
$EnvFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "TerraformUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setup Terraform for Environment '$EnvName'"


LogStep -Step 1 -Message "load environment yaml settings from Env/${EnvName}..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $EnvFolder
$spnName = $bootstrapValues.terraform.servicePrincipal
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.terraform.resourceGroup
$tenantId = $bootstrapValues.global.tenantId
$spnPwdSecretName = $bootstrapValues.terraform.servicePrincipalSecretName

$secretValueFile = Join-Path $EnvFolder "credential/$EnvName/azure_provider.tfvars"
if (-not (Test-Path $secretValueFile)) {
    New-Item -Path (Join-Path $EnvFolder "credential/$EnvName") -ItemType Directory -Force | Out-Null
    New-Item -Path $secretValueFile -ItemType File -Force | Out-Null
}
SetTerraformValue -valueFile $secretValueFile -name "tenant_id" -value $tenantId
$stateValueFile = Join-Path $provisionFolder "state/main.tf"
SetTerraformValue -valueFile $stateValueFile -name "resource_group_name" -value $rgName


LogStep -Step 2 -Message "Ensure service principal is created with password stored in key vault"
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
az group create --name $rgName --location $bootstrapValues.terraform.location | Out-Null
$azAccount = az account show | ConvertFrom-Json
$subscriptionId = $azAccount.id
$tfSp = az ad sp list --display-name $spnName | ConvertFrom-Json
LogInfo -Message "Retrieving spn password from kv '$vaultName' with name '$spnPwdSecretName'..."
$tfSpPwd = Get-OrCreatePasswordInVault2 -VaultName $vaultName -SecretName $spnPwdSecretName
if (!$tfSp) {
    LogInfo -Message "Creating service principal '$spnName' with password..."
    az ad sp create-for-rbac -n $spnName --role contributor --password $tfSpPwd.value | Out-Null
    $tfSp = az ad sp list --display-name $spnName | ConvertFrom-Json

    LogInfo -Message "Granting spn '$spnName' 'Contributor' role to subscription..."
    az role assignment create --assignee $tfSp.appId --role Contributor --scope "/subscriptions/$subscriptionId" | Out-Null

    LogInfo -Message "Granting spn '$spnName' permissions to kv '$vaultName'..."
    az keyvault set-policy `
        --name $vaultName `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --object-id $tfSp.objectId `
        --spn $tfSp.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete | Out-Null
}
else {
    LogInfo -Message "Terraform service principal '$spnName' already exists. Reset password to make sure it get updated"
    az ad sp credential reset --name $tfSp.appId --password $tfSpPwd.value | Out-Null
    $tfSp = az ad sp list --display-name $spnName | ConvertFrom-Json
}

SetTerraformValue -valueFile $secretValueFile -name "subscription_id" -value $subscriptionId
SetTerraformValue -valueFile $secretValueFile -name "client_id" -value $tfSp.appId
SetTerraformValue -valueFile $secretValueFile -name "client_secret" -value $tfSpPwd.value

LogStep -Step 3 -Message "Ensure terraform service principal has access to ACR..."
$acrName = $bootstrapValues.acr.name
$acrResourceGroup = $bootstrapValues.acr.resourceGroup
$acrFound = "$(az acr list -g $acrResourceGroup --query ""[?contains(name, '$acrName')]"" --query [].name -o tsv)"
if (!$acrFound) {
    throw "Please setup ACR first by running Setup-ContainerRegistry.ps1 script"
}
$acrId = "$(az acr show --name $acrName --query id --output tsv)"
az role assignment create --assignee $tfSp.appId --scope $acrId --role contributor | Out-Null

# LogStep -Step 4 -Message "Login as service principal '$spnName'"
# az login --service-principal -u "http://$spnName" -p $tfSpPwd.value --tenant $tenantId

LogStep -Step 4 -Message "Ensure storage account exist for tf state..." 

$storageAccount = az storage account show `
    --name $bootstrapValues.terraform.stateStorageAccountName `
    --resource-group $bootstrapValues.terraform.resourceGroup | ConvertFrom-Json
if (!$storageAccount) {
    LogInfo -Message "Creating storage account '$($bootstrapValues.terraform.stateStorageAccountName)' within resource group '$($bootstrapValues.terraform.resourceGroup)'..."
    az storage account create `
        --resource-group $bootstrapValues.terraform.resourceGroup `
        --name $bootstrapValues.terraform.stateStorageAccountName `
        --location $bootstrapValues.terraform.location `
        --sku Standard_LRS | Out-Null
    $storageKeys = az storage account keys list `
        -n $bootstrapValues.terraform.stateStorageAccountName `
        -g $bootstrapValues.terraform.resourceGroup | ConvertFrom-Json
    SetTerraformValue -valueFile $secretValueFile -name "terraform_storage_access_key" -value $storageKeys[0].value

    LogInfo -Message "Creating container '$($bootstrapValues.terraform.stateBlobContainerName)' for blob storage..."
    az storage container create `
        --name $bootstrapValues.terraform.stateBlobContainerName `
        --account-name $bootstrapValues.terraform.stateStorageAccountName `
        --account-key $storageKeys[0].value | Out-Null
}
else {
    LogInfo -Message "Storage account '$($bootstrapValues.terraform.stateStorageAccountName)' already exists."
}

SetTerraformValue -valueFile $stateValueFile -name "storage_account_name" -value $bootstrapValues.terraform.stateStorageAccountName
SetTerraformValue -valueFile $stateValueFile -name "container_name" -value $bootstrapValues.terraform.stateBlobContainerName
SetTerraformValue -valueFile $stateValueFile -name "storage_account_name" -value $bootstrapValues.terraform.stateStorageAccountName


LogStep -Step 5 -Message "Run terraform provisioning..."
$terraformStateFolder = Join-Path $provisionFolder "state"
Set-Location $terraformStateFolder
terraform init -upgrade -backend-config="access_key=$tfStorageAccessKey"
terraform plan -var-file ./terraform.tfvars -var-file $secretValueFile
terraform apply -var-file ./terraform.tfvars -var-file $secretValueFile