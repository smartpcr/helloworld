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
$credentialFolder = Join-Path $envFolder "credential"
$envCredentialFolder = Join-Path $credentialFolder $EnvName
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "TerraformUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setup devbox VM for Environment '$EnvName'"


LogStep -Step 1 -Message "load environment yaml settings from Env '$EnvName'..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvFolder
$azAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.global.resourceGroup
$tenantId = $bootstrapValues.global.tenantId
$subscriptionId = $azAccount.id
$envCredFolder = Join-Path (Join-Path $EnvFolder "credential") $EnvName
New-Item -Path $envCredFolder -ItemType Directory -Force | Out-Null


LogStep -Step 2 -Message "Ensure terraform service principal is setup..."
$terraformSpn = Get-OrCreateServicePrincipalUsingPassword `
    -ServicePrincipalName $bootstrapValues.terraform.servicePrincipal `
    -ServicePrincipalPwdSecretName $bootstrapValues.terraform.servicePrincipalSecretName `
    -VaultName $vaultName
$terraformSpnPwd = Get-OrCreatePasswordInVault2 `
    -VaultName $vaultName `
    -SecretName $bootstrapValues.terraform.servicePrincipalSecretName
az ad sp credential reset --name $bootstrapValues.terraform.servicePrincipal --password $terraformSpnPwd.value 

LogInfo -Message "Ensure terraform service principal have correct permissions..."
az role assignment create `
    --assignee $terraformSpn.appId `
    --role Contributor `
    --scope "/subscriptions/$subscriptionId" | Out-Null
az keyvault set-policy `
    --name $vaultName `
    --resource-group $bootstrapValues.kv.resourceGroup `
    --object-id $terraformSpn.objectId `
    --spn $terraformSpn.displayName `
    --certificate-permissions get list update delete `
    --secret-permissions get list set delete | Out-Null

LogStep -Step 3 -Message "Setup Windows VM..."
$winSecretValueFile = Join-Path $envCredFolder "devbox_win10.tfvars"
if (-not (Test-Path $winSecretValueFile)) {
    New-Item -Path $winSecretValueFile -ItemType File -Force | Out-Null
}
SetTerraformValue -valueFile $winSecretValueFile -name "subscription_id" -value $azAccount.id
SetTerraformValue -valueFile $winSecretValueFile -name "tenant_id" -value $tenantId
SetTerraformValue -valueFile $winSecretValueFile -name "client_id" $terraformSpn.appId 
SetTerraformValue -valueFile $winSecretValueFile -name "client_secret" $terraformSpnPwd.value 

LogInfo "Retrieve windows user password..."
$devboxUserPwdSecretName = "admin-password"
$password = Get-OrCreatePasswordInVault2 -VaultName $vaultName -SecretName $devboxUserPwdSecretName
SetTerraformValue -valueFile $winSecretValueFile -name "admin_password" -value $password.value 

$winProvisionFolder = Join-Path $vmProvisionFolder "win10"
Set-Location $winProvisionFolder
terraform init 
terraform plan -var-file $winSecretValueFile
terraform apply -var-file $winSecretValueFile


LogStep -Step 4 -Message "Setup Ubuntu VM..."
$ubuntuSecretValueFile = Join-Path $envCredFolder "devbox_ubuntu.tfvars"
if (-not (Test-Path $ubuntuSecretValueFile)) {
    New-Item -Path $ubuntuSecretValueFile -ItemType File -Force | Out-Null
}

EnsureSshCert `
    -VaultName $vaultName `
    -CertName $devboxUserPwdSecretName `
    -EnvName $EnvName `
    -ScriptFolder $scriptFolder 
$publicSshKeyFile = Join-Path $envCredentialFolder "$($devboxUserPwdSecretName).pub"
SetTerraformValue -valueFile $ubuntuSecretValueFile -name "subscription_id" -value $azAccount.id
SetTerraformValue -valueFile $ubuntuSecretValueFile -name "tenant_id" -value $tenantId
SetTerraformValue -valueFile $ubuntuSecretValueFile -name "client_id" $terraformSpn.appId 
SetTerraformValue -valueFile $ubuntuSecretValueFile -name "ssh_key_data" $publicSshKeyFile

$ubuntuProvisionFolder = Join-Path $vmProvisionFolder "ubuntu1804"
Set-Location $ubuntuProvisionFolder
terraform init 
terraform plan -var-file $ubuntuSecretValueFile
terraform apply -var-file $ubuntuSecretValueFile