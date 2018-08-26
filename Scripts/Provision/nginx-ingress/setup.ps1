# [Ingress and TLS](https://docs.microsoft.com/en-us/azure/aks/ingress)

param([string] $EnvName = "dev")

$ingressProvisionFolder = $PSScriptRoot
if (!$ingressProvisionFolder) {
    $ingressProvisionFolder = Get-Location
}
$provisionFolder = Split-Path $ingressProvisionFolder -Parent
$scriptFolder = Split-Path $provisionFolder -Parent
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "TerraformUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setup Nginx Ingress Environment '$EnvName'"
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvFolder

LogStep -Step 1 -Message "Install nginx-ingress..."
helm install stable/nginx-ingress --namespace kube-system --name nginx-ingress
LogInfo -Message "verifying external IP is available..." 
kubectl get service -l app=nginx-ingress --namespace kube-system 

# TODO: figure out how to get public IP and its id
LogInfo -Message "get cluster resource group..."
$nodeResourceGroupName = az aks show `
    --resource-group $bootstrapValues.aks.resourceGroup `
    --name $bootstrapValues.aks.clusterName `
    --query "nodeResourceGroup"
$publicIps = az network public-ip list --resource-group $nodeResourceGroupName | ConvertFrom-Json
$publicIps[1].ipAddress
$publicIps[1].id 
# $publicIpIds = az network public-ip list --query "[?ipAddress!=null]|[?contains(ipAddress, '$IP')].[id]" --output tsv

$DNSNAME = "xd-aks-ingress"
az network public-ip update --ids $publicIps[1].id --dns-name $DNSNAME

helm install stable/cert-manager --name cert-manager `
    --set ingressShim.defaultIssuerName=letsencrypt-staging `
    --set ingressShim.defaultIssuerKind=ClusterIssuer

kubectl apply -f ./cluster-issuer.yaml
kubectl apply -f ./certificates.yaml

helm install azure-samples/aks-helloworld
helm install azure-samples/aks-helloworld --set title="AKS Ingress Demo" --set serviceName="ingress-demo"

