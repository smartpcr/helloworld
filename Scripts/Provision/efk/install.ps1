param([string] $EnvName = "dev4")


$efkInstallFolder = $PSScriptRoot
if (!$efkInstallFolder) {
    $efkInstallFolder = Get-Location
}
$scriptFolder = Split-Path (Split-Path $efkInstallFolder -Parent) -Parent
$envRootFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "Modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up ELK stack for AKS cluster in '$EnvName'..."

# variables 
$namespace = "elk"

LogStep -Step 1 -Message "Connecting to AKS cluster..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --admin


LogStep -Step 2 -Message "Creating namespace '$namespace'..."
Set-Location $efkInstallFolder
kubectl apply -f .\namespace.yaml


LogStep -Step 3 -Message "Creating fluentd..."
kubectl apply -f .\fluentd.configmap.yaml
kubectl apply -f .\fluentd.serviceaccount.yaml
kubectl apply -f .\fluentd.ds.yaml


LogStep -Step 4 -Message "Creating elastic-search..."
kubectl apply -f .\elastic-search.configmap.yaml
kubectl apply -f .\elastic-search.pvc.yaml
kubectl apply -f .\elastic-search.serviceaccount.yaml
kubectl apply -f .\elastic-search.statefulset.yaml
kubectl apply -f .\elastic-search.svc.yaml


LogStep -Step 5 -Message "Creating kabana..."
kubectl apply -f .\kibana.configmap.yaml
kubectl apply -f .\kibana.pod.yaml
kubectl apply -f .\kibana.svc.yaml