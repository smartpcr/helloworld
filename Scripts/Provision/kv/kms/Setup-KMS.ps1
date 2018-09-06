param(
    [string] $EnvName = "dev"
)


$kvSampleFolder = $PSScriptRoot
if (!$kvSampleFolder) {
    $kvSampleFolder = Get-Location
}
$scriptFolder = Split-Path (Split-Path (Split-Path $kvSampleFolder -Parent) -Parent) -Parent
$envFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setting Up Pod Identity for Environment $EnvName" 


LogStep -Step 1 -Message "Login to azure and set subscription to '$($bootstrapValues.global.subscriptionName)'..." 
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $envFolder
$azureAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName
$identityName = "azureuser"
$appLabel = "demo"