param([string] $EnvName = "dev")


$envFolder = $PSScriptRoot
if (!$envFolder) {
    $envFolder = Get-Location
}
$scriptFolder = Split-Path $envFolder -Parent
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting Up Container Registry for Environment '$EnvName'"

LogStep -Step 1 -Message "Retrieving environment settings for '$EnvName'..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envFolder
$rgName = $bootstrapValues.acr.resourceGroup
$location = $bootstrapValues.acr.location
az group create --name $rgName --location $location | Out-Null
$acrName = $bootstrapValues.acr.name
$vaultName = $bootstrapValues.kv.name 
$acrPwdSecretName = $bootstrapValues.acr.passwordSecretName
LogInfo -Message "Ensure container registry with name '$acrName' is setup for subscription '$($bootstrapValues.global.subscriptionName)'..."

# use ACR
LogStep -Step 2 -Message "Ensure ACR with name '$acrName' is setup..."
$acrFound = "$(az acr list -g $rgName --query ""[?name=='$acrName']"" --query [].name -o tsv)"
if (!$acrFound -or $acrFound -ne $acrName) {
    LogInfo -Message "Creating container registry $acrName..."
    az acr create -g $rgName -n $acrName --sku Basic | Out-Null
}
else {
    LogInfo -Message "ACR with name '$acrName' already exists."
}


# login to azure 
LogStep -Step 3 -Message "Granting service principal access to ACR..."
$acrId = "$(az acr show --name $acrName --query id --output tsv)"
$spnName = $bootstrapValues.global.servicePrincipal
$spn = az ad sp list --display-name $spnName | ConvertFrom-Json
az role assignment create --assignee $spn.appId --scope $acrId --role contributor | Out-Null
# NOTE: service principal authentication didn't work with acr after role assignment
# LoginAsServicePrincipal -EnvName $EnvName -ScriptFolder $envFolder


LogStep -Step 4 -Message "Login ACR '$acrName' and retrieve password..."
az acr login -n $acrName | Out-Null
az acr update -n $acrName --admin-enabled true | Out-Null


LogStep -Step 5 -Message "Save ACR password with name '$acrPwdSecretName' to KV '$vaultName'"
$acrUsername=$acrName
$acrPassword = "$(az acr credential show -n $acrName --query ""passwords[0].value"")"
LogInfo -Message "ACR: '$acrName', user: $acrUsername, password: ***"
az keyvault secret set --vault-name $vaultName --name $acrPwdSecretName --value $acrPassword | Out-Null

<# # No need to assign contributor role (inherited from subscription scope)
# grant read/write role to service principal 
$acrId = "$(az acr show --name $acrName --query id --output tsv)"
$spAppObjId = "$(az ad sp show --id $($bootstrapValues.global.servicePrincipalAppId) --query objectId --output tsv)"
# AAD propagation error: "No matches in graph database for ..."

az role assignment create --assignee $spAppObjId --scope $acrId --role Reader 
#>

# return @{
#     acrUsername = $acrUsername
#     acrPassword = $acrPassword
# }