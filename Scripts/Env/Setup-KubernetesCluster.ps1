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


$envFolder = $PSScriptRoot
if (!$envFolder) {
    $envFolder = Get-Location
}
$scriptFolder = Split-Path $envFolder -Parent
$moduleFolder = Join-Path $scriptFolder "modules"
$credentialFolder = Join-Path $envFolder "credential"
$envCredentialFolder = Join-Path $credentialFolder $EnvName
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up container registry for environment '$EnvName'..."

$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -ScriptFolder $envFolder
$rgName = $bootstrapValues.aks.resourceGroup
$vaultName = $bootstrapValues.kv.name
$aksClusterName = $bootstrapValues.aks.clusterName
$dnsPrefix = $bootstrapValues.aks.dnsPrefix
$nodeCount = $bootstrapValues.aks.nodeCount
$vmSize = $bootstrapValues.aks.vmSize
$aksSpnAppId = $bootstrapValues.aks.servicePrincipalAppId
$aksSpnPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword

LogStep -Step 1 -Message "Login and retrieve aks spn pwd..."
az group create --name $rgName --location $bootstrapValues.aks.location | Out-Null
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
$aksSpnPwd = "$(az keyvault secret show --vault-name $vaultName --name $aksSpnPwdSecretName --query ""value"" -o tsv)"


LogStep -Step 2 -Message "Ensure SSH key is present for linux vm access..."
EnsureSshCert `
    -VaultName $vaultName `
    -CertName $bootstrapValues.aks.ssh_private_key `
    -EnvName $EnvName `
    -ScriptFolder $scriptFolder
$aksCertPublicKeyFile = Join-Path $envCredentialFolder "$($bootstrapValues.aks.ssh_private_key).pub"
$sshKeyData = Get-Content $aksCertPublicKeyFile

# this took > 30 min!! Go grab a coffee.
az aks create `
    --resource-group $rgName `
    --name $aksClusterName `
    --ssh-key-value $sshKeyData `
    --dns-name-prefix $dnsPrefix `
    --node-count $nodeCount `
    --node-vm-size $vmSize `
    --service-principal $aksSpnAppId `
    --client-secret $aksSpnPwd


LogStep -Step 5 -Message "Ensure aks service principal has access to ACR..."
$acrName = $bootstrapValues.acr.name
$acrResourceGroup = $bootstrapValues.acr.resourceGroup
$acrFound = "$(az acr list -g $acrResourceGroup --query ""[?contains(name, '$acrName')]"" --query [].name -o tsv)"
if (!$acrFound) {
    throw "Please setup ACR first by running Setup-ContainerRegistry.ps1 script"
}
$acrId = "$(az acr show --name $acrName --query id --output tsv)"
$aksSpnName = $bootstrapValues.aks.servicePrincipal
$aksSpn = az ad sp list --display-name $aksSpnName | ConvertFrom-Json
az role assignment create --assignee $aksSpn.appId --scope $acrId --role contributor | Out-Null


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