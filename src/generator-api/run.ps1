param([string] $EnvName = "dev")

$ErrorActionPreference = "Stop"
Write-Host "Deploy docker image for environment '$EnvName'..." -ForegroundColor Green 


$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}
$envFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
$apiProjectFolder = Join-Path (Join-Path $gitRootFolder "src") "generator-api"

Import-Module "$moduleFolder/common2.psm1" -Force
Import-Module "$moduleFolder/YamlUtil.psm1" -Force
Import-Module "$moduleFolder/VaultUtil.psm1" -Force
Import-Module "$moduleFolder/TerraformUtil.psm1" -Force

Write-Host "1) load environment yaml settings from Env/${EnvName}..." -ForegroundColor Green
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvFolder
$acrName = $bootstrapValues.acr.name
$spnName = $bootstrapValues.global.servicePrincipal
$rgName = $bootstrapValues.acr.resourceGroup
$acrLoginServer = "$(az acr show --resource-group $rgName --name $acrName --query "{acrLoginServer:loginServer}" --output tsv)"

Write-Host "2) Login to azure as service principal '$spnName' ..."
LoginAsServicePrincipal -EnvName $EnvName -EnvRootFolder $EnvFolder

Write-Host "3) build docker image..."
dotnet restore generator-api.csproj 
dotnet build generator-api.csproj
dotnet publish generator-api.csproj
$imageTag = "master-commitId"
$imageName = "generator-api"    
docker build -t "$($imageName):$($imageTag)" $apiProjectFolder 
docker tag "$($imageName):$($imageTag)" "$($acrLoginServer)/$($imageName):$($imageTag)"

Write-Host "4) publishing image to acr..."
az acr login -n $acrName
docker push "$($acrLoginServer)/$($imageName):$($imageTag)"