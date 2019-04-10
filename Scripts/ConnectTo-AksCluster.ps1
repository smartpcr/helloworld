param(
    [string] $EnvName = "dev",
    [switch] $asAdmin
)


$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
$envFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
if ($asAdmin) {
    az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --admin
} 
else {
    az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName | Out-Null
}

$kubeContextName = "$(kubectl config current-context)" 
Write-Host "You are now connected to kubenetes context: '$kubeContextName'" -ForegroundColor Green

Write-Host "Browse aks dashboard..." -ForegroundColor Green
az aks browse --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName