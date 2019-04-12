param([string] $EnvName = "dev")

$gitRootFolder = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }
while (-not (Test-Path (Join-Path $gitRootFolder ".git"))) {
    $gitRootFolder = Split-Path $gitRootFolder -Parent
}
$scriptFolder = Join-Path $gitRootFolder "Scripts"
if (-not (Test-Path $scriptFolder)) {
    throw "Invalid script folder '$scriptFolder'"
}

$envRootFolder = Join-Path $scriptFolder "Env"
$templateFolder = Join-Path $envRootFolder "templates"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "CertUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "CosmosDb.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle -Message "Setting up CosmosDB for environment '$EnvName'..."


LogStep -Step 1 -Message "Login and retrieve aks spn pwd..."
$bootstrapValues = Get-EnvironmentSettings -EnvName $envName -EnvRootFolder $envRootFolder
LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName | Out-Null

LogStep -Step 2 "Ensure docdb is created..."
EnsureCosmosDbAccount -AccountName $bootstrapValues.docdb.account -API $bootstrapValues.docdb.api -ResourceGroupName $bootstrapValues.global.resourceGroup -Location $bootstrapValues.global.location 
$docdbPrimaryMasterKey = GetCosmosDbAccountKey -AccountName $bootstrapValues.docdb.account -ResourceGroupName $bootstrapValues.global.resourceGroup
az keyvault secret set --vault-name $bootstrapValues.kv.name --name $bootstrapValues.docDb.keySecret --value $docdbPrimaryMasterKey | Out-Null
EnsureDatabaseExists -Endpoint "https://$($bootstrapValues.docdb.account).documents.azure.com:443/" -MasterKey $docdbPrimaryMasterKey -DatabaseName $bootstrapValues.docdb.db | Out-Null
EnsureCollectionExists `
    -AccountName $bootstrapValues.docdb.account `
    -ResourceGroupName $bootstrapValues.global.resourceGroup `
    -DbName $bootstrapValues.docdb.db `
    -CollectionName $bootstrapValues.docdb.collection `
    -CosmosDbKey $docdbPrimaryMasterKey

Write-Host "6. Ensure graph db is created..." -ForegroundColor Green
EnsureCosmosDbAccount -AccountName $bootstrapValues.graphdb.account -API $bootstrapValues.graphdb.api -ResourceGroupName $bootstrapValues.global.resourceGroup -Location $bootstrapValues.global.location 
$graphdbPrimaryMasterKey = GetCosmosDbAccountKey -AccountName $bootstrapValues.graphdb.account -ResourceGroupName $bootstrapValues.global.resourceGroup
az keyvault secret set --vault-name $bootstrapValues.kv.name --name $bootstrapValues.graphDb.keySecret --value $graphdbPrimaryMasterKey | Out-Null
EnsureDatabaseExists -Endpoint "https://$($bootstrapValues.graphdb.account).documents.azure.com:443/" -MasterKey $graphdbPrimaryMasterKey -DatabaseName $bootstrapValues.graphdb.db | Out-Null
EnsureCollectionExists `
    -AccountName $bootstrapValues.graphdb.account `
    -ResourceGroupName $bootstrapValues.global.resourceGroup `
    -DbName $bootstrapValues.graphdb.db `
    -CollectionName $bootstrapValues.graphdb.collection `
    -CosmosDbKey $graphdbPrimaryMasterKey