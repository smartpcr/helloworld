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
LogTitle -Message "Setting up istio for AKS cluster in '$EnvName'..."

LogStep -Step 1 -Message "Installing istio via helm..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --admin
LogInfo "Note: helm chart in incubator repo is no longer supported!"
$istioFolder = "/Users/xiaodongli/istio"
Set-Location $istioFolder
kubectl apply -f install/kubernetes/helm/istio/templates/crds.yaml
kubectl apply -f install/kubernetes/helm/helm-service-account.yaml
helm install install/kubernetes/helm/istio --name istio --namespace istio-system --set grafana.enabled=true,servicegraph.enabled=true,tracing.enabled=true 
