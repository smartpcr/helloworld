param([string] $EnvName = "dev")

$imageTag = "master-commitId"
$imageName = "sa-logic"

$ErrorActionPreference = "Stop"
Write-Host "Deploy docker image for environment '$EnvName'..." -ForegroundColor Green 

$logicAppFolder = $PSScriptRoot
if (!$logicAppFolder) {
    $logicAppFolder = Get-Location
}

$ScriptFolder = Join-Path (Split-Path (Split-Path (Split-Path $logicAppFolder -Parent) -Parent) -Parent) "Scripts"
$EnvFolder = Join-Path $ScriptFolder "Env"
$ModuleFolder = Join-Path $ScriptFolder "modules"

Import-Module (Join-Path $ModuleFolder "common2.psm1") -Force
Import-Module (Join-Path $ModuleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $ModuleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $ModuleFolder "TerraformUtil.psm1") -Force

Write-Host "1) load environment yaml settings from Env/${EnvName}..." -ForegroundColor Green
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $EnvFolder
$acrName = $bootstrapValues.acr.name
$rgName = $bootstrapValues.acr.resourceGroup
$acrLoginServer = "$(az acr show --resource-group $rgName --name $acrName --query "{acrLoginServer:loginServer}" --output tsv)"
if (!$acrLoginServer) {
    throw "ACR is not registered!"
}

Write-Host "2) build docker image..."
Set-Location $logicAppFolder

docker build -t "$($imageName):$($imageTag)" .
docker tag "$($imageName):$($imageTag)" "$($acrLoginServer)/$($imageName):$($imageTag)"

Write-Host "3) publishing image to acr..."
az acr login -n $acrName
docker push "$($acrLoginServer)/$($imageName):$($imageTag)"

Write-Host "4) testing..."
docker run -d -p 5050:5000 "$($acrLoginServer)/$($imageName):$($imageTag)" 