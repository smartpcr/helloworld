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
if (!$aksSpnAppId) {
    throw "AKS service principal is not setup yet"
}
$aksClientAppId = $bootstrapValues.aks.clientAppId
if (!$aksClientAppId) {
    throw "AKS client app is not setup yet"
}
$tenantId = $bootstrapValues.global.tenantId
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


LogStep -Step 3 -Message "Creating AKS cluster '$aksClusterName' within resource group '$rgName'..."
# this took > 30 min!! Go grab a coffee.
# az aks delete `
#     --resource-group $rgName `
#     --name $aksClusterName --yes 
az aks create `
    --resource-group $rgName `
    --name $aksClusterName `
    --ssh-key-value $sshKeyData `
    --enable-rbac `
    --dns-name-prefix $dnsPrefix `
    --node-count $nodeCount `
    --node-vm-size $vmSize `
    --aad-server-app-id $aksSpnAppId `
    --aad-server-app-secret $aksSpnPwd `
    --aad-client-app-id $aksClientAppId `
    --aad-tenant-id $tenantId


LogStep -Step 4 -Message "Ensure aks service principal has access to ACR..."
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


LogStep -Step 5 -Message "Set AKS context..."
# rm -rf /Users/xiaodongli/.kube/config
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --admin
$devEnvFolder = Join-Path $envFolder $EnvName
$dashboardAuthYamlFile = Join-Path $devEnvFolder "dashboard-admin.yaml"
kubectl apply -f $dashboardAuthYamlFile
$userAuthYamlFile = Join-Path $devEnvFolder "user-admin.yaml"
kubectl apply -f $userAuthYamlFile
$kubeContextName = "$(kubectl config current-context)" 
LogInfo -Message "You are now connected to kubenetes context: '$kubeContextName'" 


LogStep -Step 6 -Message "Setup helm integration..."
kubectl -n kube-system create sa tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller --upgrade

az aks browse --resource-group $($bootstrapValues.aks.resourceGroup) --name $($bootstrapValues.aks.clusterName)