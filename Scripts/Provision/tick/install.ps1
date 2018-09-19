param([string] $EnvName = "dev4")


$tickInstallFolder = $PSScriptRoot
if (!$tickInstallFolder) {
    $tickInstallFolder = Get-Location
}
$scriptFolder = Split-Path (Split-Path $tickInstallFolder -Parent) -Parent
$envRootFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "Modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up tick stack for AKS cluster in '$EnvName'..."

LogStep -Step 1 -Message "Connecting to AKS cluster..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --admin

Set-Location $tickInstallFolder
git clone https://github.com/jackzampolin/tick-charts.git charts 
$namespace = "tick"
kubectl create namespace $namespace

# $influxdb_username = "influxdb_user"
# $influxdb_password = "influxdb_password"
# $influxdb_host = "http://influxdb.tick.svc.cluster.local:8086"
# $influxdb_name = "telegraf"

LogStep -Step 2 -Message "Installing influxdb..."
helm install --name data --namespace $namespace ./charts/influxdb/

LogStep -Step 3 -Message "Installing telegraf polling..."
helm install --name polling --namespace $namespace ./charts/telegraf-s/

LogStep -Step 3 -Message "Installing telegraf host..."
helm install --name hosts --namespace $namespace ./charts/telegraf-ds/

LogStep -Step 4 -Message "Installing kapacitor..."
helm install --name alerts --namespace $namespace ./charts/kapacitor/

LogStep -Step 5 -Message "Installing chronograf..."
helm install --name dash --namespace $namespace ./charts/chronograf/

LogStep -Step 6 -Message "Open dash-chronograf and configure it..."
$chronografLoadBalancer = kubectl get svc --namespace $namespace --selector app=dash-chronograf -o json | ConvertFrom-Json
$dashboardPort = $chronografLoadBalancer.items[0].spec.ports[0].targetPort

az aks browse -g $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName
