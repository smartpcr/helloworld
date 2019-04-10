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

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}

$envFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
$credentialFolder = Join-Path $envFolder "credential"
$envCredentialFolder = Join-Path $credentialFolder $EnvName
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up AKS cluster for environment '$EnvName'..."


LogStep -Step 1 -Message "Login and retrieve aks spn pwd..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder
$azAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName 
$aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
if (!$aksSpn) {
    throw "AKS service principal is not setup yet"
}
$aksClientApp = az ad app list --display-name $bootstrapValues.aks.clientAppName | ConvertFrom-Json
if (!$aksClientApp) {
    throw "AKS client app is not setup yet"
}
$aksSpnPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword
$aksSpnPwd = "$(az keyvault secret show --vault-name $bootstrapValues.kv.name --name $aksSpnPwdSecretName --query ""value"" -o tsv)"
az group create --name $bootstrapValues.aks.resourceGroup --location $bootstrapValues.aks.location | Out-Null


LogStep -Step 2 -Message "Ensure SSH key is present for linux vm access..."
EnsureSshCert `
    -VaultName $bootstrapValues.kv.name `
    -CertName $bootstrapValues.aks.ssh_private_key `
    -EnvName $EnvName `
    -ScriptFolder $scriptFolder
$aksCertPublicKeyFile = Join-Path $envCredentialFolder "$($bootstrapValues.aks.ssh_private_key).pub"
$sshKeyData = Get-Content $aksCertPublicKeyFile


LogStep -Step 3 -Message "Ensure AKS cluster '$($bootstrapValues.aks.clusterName)' within resource group '$($bootstrapValues.aks.resourceGroup)' is created..."
LogInfo -Message "this would take 10 - 30 min, Go grab a coffee"
# az aks delete `
#     --resource-group $bootstrapValues.aks.resourceGroup `
#     --name $bootstrapValues.aks.clusterName --yes 
$aksClusters = az aks list --resource-group $bootstrapValues.aks.resourceGroup --query "[?name == '$($bootstrapValues.aks.clusterName)']" | ConvertFrom-Json
if ($null -eq $aksClusters -or $aksClusters.Count -eq 0) {
    LogInfo -Message "Creating AKS Cluster '$($bootstrapValues.aks.clusterName)'..."
    
    $currentUser = $env:USERNAME
    if (!$currentUser) {
        $currentUser = id -un
    }
    $currentMachine = $env:COMPUTERNAME
    if (!$currentMachine) {
        $currentMachine = hostname 
    }
    $tags = @()
    $tags += "environment=$EnvName" 
    $tags += "responsible=$($bootstrapValues.aks.ownerUpn)"
    $tags += "createdOn=$((Get-Date).ToString("yyyy-MM-dd"))"
    $tags += "createdBy=$currentUser"
    $tags += "fromWorkstation=$currentMachine"
    $tags += "purpose=$($bootstrapValues.aks.purpose)"
    
    az aks create `
        --resource-group $bootstrapValues.aks.resourceGroup `
        --name $bootstrapValues.aks.clusterName `
        --kubernetes-version $bootstrapValues.aks.version `
        --admin-username $bootstrapValues.aks.adminUsername `
        --ssh-key-value $sshKeyData `
        --enable-rbac `
        --dns-name-prefix $bootstrapValues.aks.dnsPrefix `
        --node-count $bootstrapValues.aks.nodeCount `
        --node-vm-size $bootstrapValues.aks.vmSize `
        --aad-server-app-id $aksSpn.appId `
        --aad-server-app-secret $aksSpnPwd `
        --aad-client-app-id $aksClientApp.appId `
        --aad-tenant-id $azAccount.tenantId `
        --tags $tags | Out-Null
}
else {
    LogInfo -Message "AKS cluster '$($bootstrapValues.aks.clusterName)' is already created."
}


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
LogInfo -Message "Grant dashboard access..."
$templatesFolder = Join-Path $envFolder "templates"
$devEnvFolder = Join-Path $envFolder $EnvName
$dashboardAuthYamlFile = Join-Path $templatesFolder "dashboard-admin.yaml"
kubectl apply -f $dashboardAuthYamlFile

LogInfo -Message "Grant current user as cluster admin..."
$currentPrincipalName = $(az ad signed-in-user show | ConvertFrom-Json).userPrincipalName 
$aadUser = az ad user show --upn-or-object-id $currentPrincipalName | ConvertFrom-Json
$userAuthTplFile = Join-Path $templatesFolder "user-admin.tpl"
$userAuthYamlFile = Join-Path $devEnvFolder "user-admin.yaml"
Copy-Item -Path $userAuthTplFile -Destination $userAuthYamlFile -Force
ReplaceValuesInYamlFile -YamlFile $userAuthYamlFile -PlaceHolder "ownerUpn" -Value $aadUser.objectId
kubectl apply -f $userAuthYamlFile

$kubeContextName = "$(kubectl config current-context)" 
LogInfo -Message "You are now connected to kubenetes context: '$kubeContextName'" 


LogStep -Step 6 -Message "Setup helm integration..."
kubectl -n kube-system create sa tiller
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller
helm init --service-account tiller --upgrade


LogStep -Step 7 -Message "Enable addons for istio integration...(will take a minute)"
az aks enable-addons `
    --resource-group $bootstrapValues.aks.resourceGroup `
    --name $bootstrapValues.aks.clusterName `
    --addons http_application_routing | Out-Null

if ($bootstrapValues.aks.useDevSpaces) {
    LogInfo -Message "Enable devspaces on AKS cluster..."
    # NOTE this still installs a preview version of devspace cli, if you installed stable version, do not install cli
    az aks use-dev-spaces `
        --resource-group $bootstrapValues.aks.resourceGroup `
        --name $bootstrapValues.aks.clusterName | Out-Null 
}

<# run the following block to switch to windows-based authentication, token expiration is much quicker 
LogInfo -Message "reset kubernetes context..."
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName
#>

# az aks browse --resource-group $($bootstrapValues.aks.resourceGroup) --name $($bootstrapValues.aks.clusterName)
