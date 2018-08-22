param([string] $EnvName = "dev")


$deployFolder = $PSScriptRoot
if (!$deployFolder) {
    $deployFolder = Get-Location
}

$serviceRootFolder = (Split-Path (Split-Path (Split-Path $deployFolder -Parent) -Parent) -Parent)
$ScriptFolder = Join-Path (Split-Path (Split-Path $serviceRootFolder -Parent) -Parent) "Scripts"
$EnvFolder = Join-Path $ScriptFolder "Env"
$ModuleFolder = Join-Path $ScriptFolder "modules"
$imageBranchName = "master"
$imageCommitId = "commitId"
$serviceName = "Sentiment Analysis"
$imageTag = "$($imageBranchName)-$($imageCommitId)"

Import-Module (Join-Path $ModuleFolder "common2.psm1") -Force
Import-Module (Join-Path $ModuleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $ModuleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $ModuleFolder "TerraformUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $ScriptFolder
LogTitle -Message "Deploy '$($serviceName)' with tag '$($imageTag)' to AKS in Environment '$EnvName'"


LogStep -Step 1 -Message "load environment yaml settings from Env '$EnvName'..." 
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $EnvFolder
$acrName = $bootstrapValues.acr.name
$rgName = $bootstrapValues.acr.resourceGroup
$acrLoginServer = "$(az acr show --resource-group $rgName --name $acrName --query "{acrLoginServer:loginServer}" --output tsv)"
if (!$acrLoginServer) {
    throw "ACR is not registered!"
}
$saFontendYamlFile = Join-Path $deployFolder "sa-frontend.yaml"
$saWebAppYamlFile = Join-Path $deployFolder "sa-webapp.yaml"
$saLogicYamlFile = Join-Path $deployFolder "sa-logic.yaml"

ReplaceValuesInYamlFile -YamlFile $saFontendYamlFile -PlaceHolder "saFrontendImageName" -Value "sa-frontend"
ReplaceValuesInYamlFile -YamlFile $saWebAppYamlFile -PlaceHolder "saWebAppImageName" -Value "sa-webappp"
ReplaceValuesInYamlFile -YamlFile $saLogicYamlFile -PlaceHolder "saLogicImageName" -Value "sa-logic"
ReplaceValuesInYamlFile -YamlFile $saFontendYamlFile -PlaceHolder "acrLoginServer" -Value $acrLoginServer
ReplaceValuesInYamlFile -YamlFile $saWebAppYamlFile -PlaceHolder "acrLoginServer" -Value $acrLoginServer
ReplaceValuesInYamlFile -YamlFile $saLogicYamlFile -PlaceHolder "acrLoginServer" -Value $acrLoginServer
ReplaceValuesInYamlFile -YamlFile $saFontendYamlFile -PlaceHolder "saFrontendBranch" -Value $imageBranchName
ReplaceValuesInYamlFile -YamlFile $saWebAppYamlFile -PlaceHolder "saWebAppBranch" -Value $imageBranchName
ReplaceValuesInYamlFile -YamlFile $saLogicYamlFile -PlaceHolder "saLogicBranch" -Value $imageBranchName
ReplaceValuesInYamlFile -YamlFile $saFontendYamlFile -PlaceHolder "saFrontendCommitId" -Value $imageCommitId
ReplaceValuesInYamlFile -YamlFile $saWebAppYamlFile -PlaceHolder "saWebAppCommitId" -Value $imageCommitId
ReplaceValuesInYamlFile -YamlFile $saLogicYamlFile -PlaceHolder "saLogicCommitId" -Value $imageCommitId

Write-Host "2) Login to service principal '$($bootstrapValues.terraform.servicePrincipal)'..." -ForegroundColor Green
# az login --service-principal -u "http://$($bootstrapValues.terrafom.servicePrincipal)" -p "$deploymentServicePrincipalPassword" --tenant "$TenantId"
# az account set -s "$DeploymentSubscriptionId"
az aks get-credentials -g "$($bootstrapValues.aks.resourceGroup)" -n "$($bootstrapValues.aks.clusterName)"

Write-Host "3) Deploy to AKS cluster..." -ForegroundColor Green
Set-Location $deployFolder 
kubectl create -f "sa-frontend.yaml"
kubectl create -f "sa-webapp.yaml"
kubectl create -f "sa-logic.yaml"
