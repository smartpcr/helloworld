<#
    this script retrieve settings based on target environment
    1) use service principal to authenticate 
    2) use same key vault
    3) create certificate and add to key vault
    4) create service principle with cert auth
    5) grant permission to service principle
        a) key vault
        b) resource group
#>
param([string] $EnvName = "dev")

$ErrorActionPreference = "Stop"

$envFolder = $PSScriptRoot
if (!$envFolder) {
    $envFolder = Get-Location
}
$scriptFolder = Split-Path $envFolder -Parent
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up container registry for environment '$EnvName'..."

$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -ScriptFolder $scriptFolder
$rgName = $bootstrapValues.global.resourceGroup
$vaultName = $bootstrapValues.kv.name
$aksClusterName = $bootstrapValues.aks.clusterName
$dnsPrefix = $bootstrapValues.aks.dnsPrefix
$nodeCount = $bootstrapValues.aks.nodeCount
$vmSize = $bootstrapValues.aks.vmSize
$aksSpnAppId = $bootstrapValues.aks.servicePrincipalAppId
$aksSpnPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword

# login to azure 
LoginAsServicePrincipal -EnvName $EnvName -ScriptFolder $scriptFolder

$aksSpnPwd = "$(az keyvault secret show --vault-name $vaultName --name $aksSpnPwdSecretName --query ""value"" -o tsv)"

# this took > 30 min!! Go grab a coffee.
az aks create `
    --resource-group $rgName `
    --name $aksClusterName `
    --generate-ssh-keys `
    --dns-name-prefix $dnsPrefix `
    --node-count $nodeCount `
    --node-vm-size $vmSize `
    --service-principal $aksSpnAppId `
    --client-secret $aksSpnPwd

# grant aks read access to acr
aksSvcPrincipalAppId="$(az aks show -g $rgName -n $aksClusterName --query ""servicePrincipalProfile.clientId"" -o tsv)" 
acrId="$(az acr show -n xdcontainerregistry -g $rgName --query ""id"" -o tsv)"
az role assignment create --assignee $aksSvcPrincipalAppId --role Reader --scope $acrId

# set acr secrets in AKS
$acrName = $bootstrapValues.acr.name
$acrPwdSecretName = $bootstrapValues.acr.passwordSecretName
$acrEmail = $bootstrapValues.acr.email


ACR_NAME="xdcontainerregistry"
SERVICE_PRINCIPAL_NAME="xd_acr-service-principal"
EMAIL="xiaodoli@microsoft.com"
ACR_LOGIN_SERVER=$(az acr show -n $acrName --query loginServer -o tsv)
ACR_REGISTRY_ID=$(az acr show -n $acrName --query id -o tsv)

az ad sp list 
SP_PASSWD=$(az ad sp create-for-rbac -n $SERVICE_PRINCIPAL_NAME --role Reader --scopes $ACR_REGISTRY_ID --query password -o tsv)
CLIENT_ID=$(az ad sp show --id http://$SERVICE_PRINCIPAL_NAME --query appId -o tsv)
echo "Service principal ID: $CLIENT_ID"
echo "Service principal password: $SP_PASSWD"
k create secret docker-registry acr-auth --docker-server $ACR_LOGIN_SERVER --docker-username $CLIENT_ID --docker-password $SP_PASSWD --docker-email $EMAIL

# create deployment using ACR image
k create -f src/aks-helloworld/aci-helloworld.yaml 
k apply -f src/aks-helloworld/aci-helloworld.yaml 

# set nodes count to desired number (this took ~10 min, super slow!!)
az aks scale -n $aksClusterName -g $rgName -c 10 
az aks scale -n $aksClusterName -g $rgName -c 2

# shows current control plane and agent pool version, available upgrade versions
# az aks get-versions -n $aksClusterName -g $rgName --location eastus

# upgrades
az aks upgrade -n $aksClusterName -g $rgName -k 1.9.6

# switch to different cluster
k config use-context minikube
k config use-context $aksClusterName

# use helm/chart (tiller service deployed to kube-system namespace)
kubectl create -f ./helm-rbac.yaml 
helm init --service-account tiller
helm search
helm repo update
helm install stable/mysql
helm list 
helm delete ugly-billygoat

docker pull microsoft/aci-helloworld
docker images
docker tag microsoft/aci-helloworld xdcontainerregistry.azurecr.io/aci-helloworld:v1 
docker push xdcontainerregistry.azurecr.io/aci-helloworld
az acr repository list -n xdContainerRegistry -o table  
az acr repository show-tags -n xdContainerRegistry --repository aci-helloworld -o table