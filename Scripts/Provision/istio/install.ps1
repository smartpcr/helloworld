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

LogStep -Step 2 -Message "Verify pre-requirement for sidecar injection..."
LogInfo -Message "Verifying pre-requirement in AKS cluster..."
kubectl version --short # client >= 1.10, server >= 1.9
kubectl api-versions |grep admissionregistration
# TODO: make sure http routing is enabled as addon in aks

LogInfo -Message "Test with sample app..."
kubectl label namespace default istio-injection=enabled
kubectl get ns -L istio-injection 
Set-Location $istioFolder
kubectl apply -f ./samples/bookinfo/platform/kube/bookinfo.yaml

LogInfo -Message "Verifying sidecar injection..."
kubectl get svc 
kubectl get pods
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml
kubectl get gateway 
$ingressGateway = kubectl -n istio-system get service istio-ingressgateway -o json | ConvertFrom-Json
$ingressHost = $ingressGateway.status.loadBalancer.ingress[0].ip
$ingressPort = ($ingressGateway.spec.ports | ? { $_.name -eq "http2" }).port 
$ingressSslPort = ($ingressGateway.spec.ports | ? { $_.name -eq "https" }).port 
open "http://$($ingressHost):$ingressPort/productpage"
open "https://$($ingressHost):$ingressSslPort/productpage"

LogInfo -Message "Cleanup book info app..."
./samples/bookinfo/platform/kube/cleanup.sh