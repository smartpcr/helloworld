param([string] $EnvName = "dev")

$spinnakerFolder = $PSScriptRoot
if (!$spinnakerFolder) {
    $spinnakerFolder = Get-Location
}
$scriptFolder = Split-Path (Split-Path $spinnakerFolder -Parent) -Parent
$moduleFolder = Join-Path $scriptFolder "Modules"
$envRootFolder = Join-Path $scriptFolder "Env"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
$spnName = "Spinnaker"
$spnPasswordSecret = "azureuser-pwd"
$rgName = "spinnaker"
$vaultName = "xdspinnaker"
$spinnakerAccountNmae = "xd-spinnaker"

LogTitle -Message "Setting up spinnaker in '$EnvName'..."
LogStep -Step 1 -Message "Installing halyard..."
curl -O https://raw.githubusercontent.com/spinnaker/halyard/master/install/macos/InstallHalyard.sh
$currentUser = whoami
sudo bash InstallHalyard.sh --user $currentUser
hal -v

LogStep -Step 2 -Message "Enable azure provider..."
$azAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName
az group create --name $rgName --location $bootstrapValues.global.location | Out-Null
az keyvault create --resource-group $rgName --name $vaultName | Out-Null

$spinnakerSpn = Get-OrCreateServicePrincipalUsingPassword `
    -ServicePrincipalName $spnName `
    -ServicePrincipalPwdSecretName $spnPasswordSecret `
    -VaultName $vaultName

az keyvault set-policy --secret-permissions get --name $vaultName --spn $spinnakerSpn.appId | Out-Null

$spnPassword = Get-OrCreatePasswordInVault2 -VaultName $vaultName -SecretName $spnPasswordSecret

$spnPassword.value | hal config provider azure account add $spinnakerAccountNmae `
  --client-id $spinnakerSpn.appId `
  --tenant-id $azAccount.tenantId `
  --subscription-id $azAccount.id `
  --default-key-vault $vaultName `
  --default-resource-group $rgName `
  --app-key 


LogStep -Step 3 -Message "Distribute spinnaker to AKS..."
hal config deploy edit --type distributed --account-name $spinnakerAccountNmae