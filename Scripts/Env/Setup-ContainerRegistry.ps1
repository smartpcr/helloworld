param([string] $EnvName = "dev")

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
Import-Module "$scriptFolder\..\modules\common.psm1" -Force
Import-Module "$scriptFolder\..\modules\CertUtil.psm1" -Force

$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -ScriptFolder $scriptFolder
$rgName = $bootstrapValues.global.resourceGroup
$acrName = $bootstrapValues.acr.name
$vaultName = $bootstrapValues.kv.name 
$acrPwdSecretName = $bootstrapValues.acr.passwordSecretName

# login to azure 
Connect-ToAzure -EnvName $EnvName -ScriptFolder $scriptFolder

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

Set-AzureKeyVaultSecret -VaultName $vaultName -Name $acrPwdSecretName -SecretValue ($acrPassword | ConvertTo-SecureString -AsPlainText -Force)

return @{
    acrUsername = $acrUsername
    acrPassword = $acrPassword
}