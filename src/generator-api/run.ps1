param([string] $EnvName = "dev")

$ErrorActionPreference = "Stop"
Write-Host "Deploy docker image for environment '$EnvName'..." -ForegroundColor Green 

$apiProjectFolder = $PSScriptRoot
if (!$apiProjectFolder) {
    $apiProjectFolder = Get-Location
}

$EnvFolder = "$apiProjectFolder/../../Scripts/Env"
$ScriptFolder = "$apiProjectFolder/../../Scripts"
Import-Module "$ScriptFolder/modules/common2.psm1" -Force
Import-Module "$ScriptFolder/modules/YamlUtil.psm1" -Force
Import-Module "$ScriptFolder/modules/VaultUtil.psm1" -Force
Import-Module "$ScriptFolder/modules/TerraformUtil.psm1" -Force

Write-Host "1) load environment yaml settings from Env/${EnvName}..." -ForegroundColor Green
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvFolder
$acrName = $bootstrapValues.acr.name
$spnName = $bootstrapValues.global.servicePrincipal
$rgName = $bootstrapValues.global.resourceGroup
$acrLoginServer = "$(az acr show --resource-group $rgName --name $acrName --query "{acrLoginServer:loginServer}" --output tsv)"

Write-Host "2) Login to azure as service principal '$spnName' ..."
LoginAsServicePrincipal -EnvName $EnvName -ScriptFolder $EnvFolder

Write-Host "3) build docker image..."
dotnet restore generator-api.csproj 
dotnet build generator-api.csproj
dotnet publish generator-api.csproj
$imageTag = "master-commitId"
$imageName = "generator-api"    
docker build -t "$($imageName):$($imageTag)" .
docker tag "$($imageName):$($imageTag)" "$($acrLoginServer)/$($imageName):$($imageTag)"

Write-Host "4) publishing image to acr..."
az acr login -n $acrName
docker push "$($acrLoginServer)/$($imageName):$($imageTag)"