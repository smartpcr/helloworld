param([string] $EnvName = "dev")

$imageTag = "master-commitId"
$imageName = "sa-webapp"


$webApiFolder = $PSScriptRoot
if (!$webApiFolder) {
    $webApiFolder = Get-Location
}

$ScriptFolder = Join-Path (Split-Path (Split-Path (Split-Path $webApiFolder -Parent) -Parent) -Parent) "Scripts"
$EnvFolder = Join-Path $ScriptFolder "Env"
$ModuleFolder = Join-Path $ScriptFolder "modules"

Import-Module (Join-Path $ModuleFolder "common2.psm1") -Force
Import-Module (Join-Path $ModuleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $ModuleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $ModuleFolder "TerraformUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $ScriptFolder
LogTitle -Message "Deploy Image '$imageName' with Tag '$imageTag' in Environment '$EnvName'"


LogStep -Step 1 -Message "load environment yaml settings from Env/${EnvName}..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $EnvFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null
$acrName = $bootstrapValues.acr.name
$rgName = $bootstrapValues.acr.resourceGroup
$acrLoginServer = "$(az acr show --resource-group $rgName --name $acrName --query "{acrLoginServer:loginServer}" --output tsv)"
if (!$acrLoginServer) {
    throw "ACR is not registered!"
}


LogStep -Step 2 -Message "build docker image..."
Set-Location $webApiFolder
mvn install


LogStep -Step 3 -Message "publishing image to acr..."
docker build -t "$($imageName):$($imageTag)" .
docker tag "$($imageName):$($imageTag)" "$($acrLoginServer)/$($imageName):$($imageTag)"
az acr login -n $acrName
docker push "$($acrLoginServer)/$($imageName):$($imageTag)"


LogStep -Step 4 -Message "Starting image on local..."
$dockerContainerFound = docker container ls -aqf "name=$imageName"
if ($dockerContainerFound) {
    docker container stop $imageName | Out-Null
    docker container rm $imageName | Out-Null
}
docker run -d -p 8080:8080 --name $imageName -e SA_LOGIC_API_URL='http://172.17.0.4:5000' "$($acrLoginServer)/$($imageName):$($imageTag)" | Out-Null
# docker exec -it $imageName /bin/sh 