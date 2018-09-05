param([string] $EnvName = "dev")

$istioInstallFolder = $PSScriptRoot
if (!$istioInstallFolder) {
    $istioInstallFolder = Get-Location
}
$scriptFolder = Split-Path (Split-Path $istioInstallFolder -Parent) -Parent
$envRootFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "Modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Rollback istio for AKS cluster in '$EnvName'..."


LogStep -Step 1 -Message "Clear istio resources using helm..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --admin

helm delete --purge istio
kubectl delete -f install/kubernetes/helm/istio/templates/crds.yaml -n istio-system
