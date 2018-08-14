<#
    this script setup terraform environment
    1) load environment yaml settings from Env/${EnvName}
    2) check if client secret (password for service principal) is available, if not, login as user, create service principal and password, store password to key vault and also download it to credential folder (blocked from checkin!!!)
    3) login as service principal using password
    4) provision storage for terraform remote state 
#>
param([string] $EnvName = "dev")

$ErrorActionPreference = "Stop"
Write-Host "Setting up container registry for environment '$EnvName'..." -ForegroundColor Green 

$scriptFolder = $PSScriptRoot
if (!$scriptFolder) {
    $scriptFolder = Get-Location
}
Import-Module "$scriptFolder\..\modules\common2.psm1" -Force
Import-Module "$scriptFolder\..\modules\YamlUtil.psm1" -Force
Import-Module "$scriptFolder\..\modules\VaultUtil.psm1" -Force

Write-Host "1) load environment yaml settings from Env/${EnvName}..." -ForegroundColor Green
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder "$scriptFolder/../Env"
$spnName = $bootstrapValues.terraform.servicePrincipal
$vaultName = $bootstrapValues.kv.name
$tenantId = $bootstrapValues.global.tenantId
$spnPwdSecretName = $bootstrapValues.terraform.servicePrincipalSecretName
$spnPasswordFile = "$scriptFolder/../credential/$spnPwdSecretName.tfvars"

Write-Host "2) Ensure service principal is created with password stored in key vault" -ForegroundColor Green
if (-not (Test-Path $spnPasswordFile)) {
    az login 
    az account set --subscription $bootstrapValues.global.subscriptionName
    $azAccount = az account show 
    $subscriptionId = $azAccount.id
    $tfSp = az ad sp list --display-name $spnName | ConvertFrom-Json
    $tfSpPwd = Get-OrCreatePasswordInVault2 -VaultName $vaultName -SecretName $spnPwdSecretName
    if (!$tfSp) {
        az ad sp create-for-rbac -n $spnName --role contributor --password $tfSpPwd.value 
        $tfSp = az ad sp list --display-name $spnName | ConvertFrom-Json
        az role assignment create --assignee $tfSp.appId --role Contributor --scope "/subscriptions/$subscriptionId"
    }
    "client_secret=`"$tfSpPwd`"" | Out-File $spnPasswordFile
}

Write-Host "3) Login as service principal '$spnName'" -ForegroundColor Green
az login --service-principal -u "http://$tfSp.appId" -p $tfSpPwd.value --tenant $tenantId

Write-Host "4) Provisioning storage account..." -ForegroundColor Green
Set-Location "$scriptFolder/state"
terraform init 
terraform plan --var-file ./variables.tfvars --var-file $spnPasswordFile
terraform apply --var-file ./variables.tfvars --var-file $spnPasswordFile