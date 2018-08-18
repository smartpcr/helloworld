param([string] $EnvName = "dev")

$ErrorActionPreference = "Stop"
Write-Host "Setting up container registry for environment '$EnvName'..."

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
Import-Module "$scriptFolder\..\modules\YamlUtil.psm1" -Force
Import-Module "$scriptFolder\..\modules\common2.psm1" -Force
Import-Module "$scriptFolder\..\modules\CertUtil.psm1" -Force
Import-Module "$scriptFolder\..\modules\VaultUtil.psm1" -Force

$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -ScriptFolder $scriptFolder
$rgName = $bootstrapValues.global.resourceGroup
$acrName = $bootstrapValues.acr.name
$vaultName = $bootstrapValues.kv.name 
$acrPwdSecretName = $bootstrapValues.acr.passwordSecretName
Write-Host "Ensure container registry with name '$acrName' is setup for subscription '$($bootstrapValues.global.subscriptionName)'..."

# login to azure 
LoginAsServicePrincipal -EnvName $EnvName -ScriptFolder $scriptFolder

# use ACR
$acrFound = "$(az acr list -g $rgName --query ""[?contains(name, '$acrName')]"" --query [].name -o tsv)"
if (!$acrFound) {
    Write-Host "Creating container registry $acrName..."
    az acr create -g $rgName -n $acrName --sku Basic
}

az acr login -n $acrName
az acr update -n $acrName --admin-enabled true 
 
# get ACR username/password
$acrUsername=$acrName
$acrPassword = "$(az acr credential show -n $acrName --query ""passwords[0].value"")"

Write-Host "ACR $acrName is created with user: $acrUsername and password: $acrPassword"

az keyvault secret set --vault-name $vaultName --name $acrPwdSecretName --value $acrPassword

<# # No need to assign contributor role (inherited from subscription scope)
# grant read/write role to service principal 
$acrId = "$(az acr show --name $acrName --query id --output tsv)"
$spAppObjId = "$(az ad sp show --id $($bootstrapValues.global.servicePrincipalAppId) --query objectId --output tsv)"
# AAD propagation error: "No matches in graph database for ..."

az role assignment create --assignee $spAppObjId --scope $acrId --role Reader 
#>

return @{
    acrUsername = $acrUsername
    acrPassword = $acrPassword
}