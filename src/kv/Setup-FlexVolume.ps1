<#
    this script does the following
    1) create a new service principal using pwd
    2) grant readonly access to kv secrets and certs
    3) create a daemonset and mount flex volume to each node
    4) a helloworld app that retrieve docdb connection string from kv flex volume
#>
param(
    [string] $EnvName = "dev"
)


$kvSampleFolder = $PSScriptRoot
if (!$kvSampleFolder) {
    $kvSampleFolder = Get-Location
}
$scriptFolder = Join-Path (Split-Path (Split-Path $kvSampleFolder -Parent) -Parent) "Scripts"
$envFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setting Up KV Flex Volume for Environment $EnvName" 

$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $envFolder
$clusterContextName = $bootstrapValues.aks.clusterName

LogStep -Step 1 -Message "Login to azure and set subscription to '$($bootstrapValues.global.subscriptionName)'..." 
$azureAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName


LogStep -Step 2 -Message "Creating service principal '$($bootstrapValues.kvSample.servicePrincipal)'..."
$spn = Get-OrCreateServicePrincipalUsingPassword `
    -ServicePrincipalName $bootstrapValues.kvSample.servicePrincipal `
    -ServicePrincipalPwdSecretName $bootstrapValues.kvSample.servicePrincipalPwd `
    -VaultName $bootstrapValues.kv.name


LogStep -Step 3 -Message "Granting spn '$($spn.displayName)' permission to keyvault '$($bootstrapValues.kv.name)'..."
az keyvault set-policy `
    --name $bootstrapValues.kv.name `
    --resource-group $bootstrapValues.kv.resourceGroup `
    --object-id $spn.objectId `
    --spn $spn.displayName `
    --certificate-permissions get  `
    --secret-permissions get | Out-Null


LogStep -Step 4 -Message "Install daemonset 'keyvault-flexvolume' to AKS Cluster '$($bootstrapValues.aks.clusterName)'..."
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName
kubectl apply -f "https://raw.githubusercontent.com/Azure/kubernetes-keyvault-flexvol/master/deployment/kv-flexvol-installer.yaml"


LogStep -Step 5 -Message "Create KV secret using spn '$($spn.displayName)' and its password '***'..."
$kvCredName = "kvcreds"
$spnPwdSecret = az keyvault secret show --vault-name $bootstrapValues.kv.name --name $bootstrapValues.kvSample.servicePrincipalPwd | ConvertFrom-Json
kubectl create secret generic $kvCredName --from-literal clientid=$spn.appId --from-literal clientsecret=$spnPwdSecret.value

LogStep -Step 6 -Message "Deploy KV access sample application..."
$secretName = "appsecret1"
$secretValue = "TopSecret!"
az keyvault secret set --vault-name $bootstrapValues.kv.name --name $secretName --value $secretValue | Out-Null
$podYamlFile = Join-Path $kvSampleFolder "TestPod.yml"
ReplaceValuesInYamlFile -YamlFile $podYamlFile -PlaceHolder "tenantId" -Value $bootstrapValues.global.tenantId
ReplaceValuesInYamlFile -YamlFile $podYamlFile -PlaceHolder "subscriptionId" -Value $azureAccount.id
ReplaceValuesInYamlFile -YamlFile $podYamlFile -PlaceHolder "rgName" -Value $bootstrapValues.kv.resourceGroup
ReplaceValuesInYamlFile -YamlFile $podYamlFile -PlaceHolder "vaultName" -Value $bootstrapValues.kv.name
ReplaceValuesInYamlFile -YamlFile $podYamlFile -PlaceHolder "secretName" -Value $secretName
ReplaceValuesInYamlFile -YamlFile $podYamlFile -PlaceHolder "kvSecrets" -Value $kvCredName
kubectl apply -f $podYamlFile 


LogStep -Step 7 -Message "Verify secret is mounted to pod..."

<# list ip addr for cluster nodes
kubectl get pods -o wide # get nodename
$aksResourceGroup = az aks show --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName --query nodeResourceGroup -o tsv
az vm list-ip-addresses --resource-group $aksResourceGroup -o table 
az vm user update `
  --resource-group MC_myResourceGroup_myAKSCluster_eastus `
  --name aks-nodepool1-33901137-2 `
  --username azureuser `
  --ssh-key-value ~/.ssh/id_rsa.pub

kubectl run -it --rm aks-ssh --image=debian
#>

kubectl describe pod keyvault-demo
kubectl exec -it keyvault-demo cat "/kvmnt/$secretName"