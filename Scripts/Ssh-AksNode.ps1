param(
    [string] $EnvName = "dev",
    [string] $NodeName = "aks-nodepool1-33901137-0"
)


$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
$envFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
az aks get-credentials --resource-group $bootstrapValues.aks.resourceGroup --name $bootstrapValues.aks.clusterName | Out-Null
$kubeContextName = "$(kubectl config current-context)" 
LogStep -Step 1 -Message "You are now connected to kubenetes context: '$kubeContextName'" 

$nodeResourceGroup = "$(az aks show --resource-group $($bootstrapValues.aks.resourceGroup) --name $($bootstrapValues.aks.clusterName) --query nodeResourceGroup -o tsv)"
$vm = az vm show -g $nodeResourceGroup -n $NodeName | ConvertFrom-Json
[string]$pipId = $vm.networkProfile.networkInterfaces.id
$nicName = $pipId.Substring($pipId.LastIndexOf("/") + 1)
$ipConfig = az network nic ip-config list --nic-name $nicName -g $nodeResourceGroup | ConvertFrom-Json

$publicIpName = "jumpbox"
az network public-ip create -g $nodeResourceGroup -n $publicIpName | Out-Null
az network nic ip-config update -g $nodeResourceGroup --nic-name $nicName --name $ipConfig.name --public-ip-address $publicIpName | Out-Null
$pip = az network public-ip show -g $nodeResourceGroup -n $publicIpName | ConvertFrom-Json
$sshPrivateKeyFile = "$envFolder\credential\$EnvName\$($bootstrapValues.aks.ssh_private_key)"
ssh-copy-id -i ~/.ssh/id_rsa.pub remote-host
ssh -i $sshPrivateKeyFile "$($bootstrapValues.aks.adminUsername)@$($pip.ipAddress)"
