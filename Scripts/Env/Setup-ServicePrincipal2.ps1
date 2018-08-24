<#
    this script retrieve settings based on target environment
    1) create azure resource group
    2) create key vault
    3) create certificate and add to key vault
    4) create service principle with cert auth
    5) grant permission to service principle
        a) key vault
        b) resource group
#>
param([string] $EnvName = "dev")


$envFolder = $PSScriptRoot
if (!$envFolder) {
    $envFolder = Get-Location
}
$scriptFolder = Split-Path $envFolder -Parent
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setting Up Service Principal for Environment $EnvName" 

$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $envFolder

# login and set subscription 
LogStep -Step 1 -Message "Login to azure and set subscription to '$($bootstrapValues.global.subscriptionName)'..." 
$azureAccount = LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName

$spnName = $bootstrapValues.global.servicePrincipal
$vaultName = $bootstrapValues.kv.name
$rgName = $bootstrapValues.global.resourceGroup
$subscriptionId = $azureAccount.id 
$currentEnvFolder = Join-Path $envFolder $EnvName
$devValueYamlFile = Join-Path $currentEnvFolder "values.yaml"
$values = Get-Content $devValueYamlFile -Raw | ConvertFrom-Yaml

# create resource group 
LogStep -Step 2 -Message "Creating resource group '$($rgName)' at location '$($bootstrapValues.global.location)'..."
$rgGroups = az group list --query "[?name=='$rgName']" | ConvertFrom-Json
if (!$rgGroups -or $rgGroups.Count -eq 0) {
    LogInfo -Message "Creating resource group '$rgName' in location '$($bootstrapValues.global.location)'"
    az group create --name $rgName --location $bootstrapValues.global.location | Out-Null
}

# create key vault 
LogStep -Step 3 -Message "Creating key vault '$vaultName' within resource group '$($bootstrapValues.kv.resourceGroup)' at location '$($bootstrapValues.kv.location)'..."
$kvrg = az group list --query "[?name=='$($bootstrapValues.kv.resourceGroup)']" | ConvertFrom-Json
if (!$kvrg) {
    az group create --name $bootstrapValues.kv.resourceGroup --location $bootstrapValues.kv.location | Out-Null
}
$kvs = az keyvault list --resource-group $bootstrapValues.kv.resourceGroup --query "[?name=='$vaultName']" | ConvertFrom-Json
if ($kvs.Count -eq 0) {
    LogInfo -Message "Creating Key Vault $vaultName..." 
    
    az keyvault create `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --name $vaultName `
        --sku standard `
        --location $bootstrapValues.global.location `
        --enabled-for-deployment $true `
        --enabled-for-disk-encryption $true `
        --enabled-for-template-deployment $true | Out-Null
}
else {
    LogInfo -Message "Key vault $($vaultName) is already created" 
}

# create service principal (SPN) for cluster provision
LogStep -Step 4 -Message "Creating service principal '$($spnName)'..." 
$sp = az ad sp list --display-name $spnName | ConvertFrom-Json
if (!$sp) {
    LogInfo -Message "Creating service principal with name '$spnName'..." 

    $certName = $spnName
    EnsureCertificateInKeyVault -VaultName $vaultName -CertName $certName -ScriptFolder $envFolder
    
    az ad sp create-for-rbac -n $spnName --role contributor --keyvault $vaultName --cert $certName | Out-Null
    $sp = az ad sp list --display-name $spnName | ConvertFrom-Json
    LogInfo -Message "Granting spn '$spnName' 'contributor' role to subscription" 
    az role assignment create --assignee $sp.appId --role Contributor --scope "/subscriptions/$subscriptionId" | Out-Null

    LogInfo -Message "Granting spn '$spnName' permissions to keyvault '$vaultName'" 
    az keyvault set-policy `
        --name $vaultName `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --object-id $sp.objectId `
        --spn $sp.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete | Out-Null
}
else {
    LogInfo -Message "Service principal '$spnName' already exists." 
}


if ($bootstrapValues.global.aks -eq $true) {
    LogStep -Step 5 -Message "Creating AKS service principal '$($bootstrapValues.aks.servicePrincipal)'..." 
    $aksrg = az group list --query "[?name=='$($bootstrapValues.aks.resourceGroup)']" | ConvertFrom-Json
    if (!$aksrg) {
        az group create --name $bootstrapValues.aks.resourceGroup --location $bootstrapValues.aks.location | Out-Null
    }

    $aksSpnName = $bootstrapValues.aks.servicePrincipal
    $askSpnPwdSecretName = $bootstrapValues.aks.servicePrincipalPassword
    Get-OrCreateAksServicePrincipal `
        -ServicePrincipalName $aksSpnName `
        -ServicePrincipalPwdSecretName $askSpnPwdSecretName `
        -VaultName $vaultName `
        -ScriptFolder $envFolder `
        -EnvName $EnvName | Out-Null
    
    $aksSpn = az ad sp list --display-name $aksSpnName | ConvertFrom-Json
    LogInfo -Message "set groupMembershipClaims to [All] to spn '$aksSpnName'"
    az ad app update --id $aksSpn.appId --set groupMembershipClaims="All" | Out-Null
    
    # write to values.yaml
    $values.aksServicePrincipalAppId = $aksSpn.appId
    LogInfo -Message "Granting spn '$aksSpnName' 'Contributor' role to resource group '$($bootstrapValues.aks.resourceGroup)'" 
    az role assignment create `
        --assignee $aksSpn.appId `
        --role Contributor `
        --resource-group $bootstrapValues.aks.resourceGroup | Out-Null
    LogInfo -Message "Granting spn '$aksSpnName' permissions to keyvault '$vaultName'" 
    az keyvault set-policy `
        --name $vaultName `
        --resource-group $bootstrapValues.kv.resourceGroup `
        --object-id $aksSpn.objectId `
        --spn $aksSpn.displayName `
        --certificate-permissions get list update delete `
        --secret-permissions get list set delete | Out-Null

    LogInfo -Message "Creating AKS Client App '$($bootstrapValues.aks.clientAppName)'..."
    Get-OrCreateAksClientApp -EnvRootFolder $envFolder -EnvName $EnvName | Out-Null

    $aksClientApp = az ad app list --display-name $bootstrapValues.aks.clientAppName | ConvertFrom-Json
    $values.aksClientAppId = $aksClientApp[0].appId
}

# write to values.yaml
$values.subscriptionId = $azureAccount.id
$values.servicePrincipalAppId = $sp.appId
$values.tenantId = $azureAccount.tenantId  
$values | ConvertTo-Yaml | Out-File $devValueYamlFile -Encoding utf8

# connect as service principal 
# LoginAsServicePrincipal -EnvName $EnvName -ScriptFolder $envFolder
LogTitle "Remember to manually grant aad app request before creating aks cluster!"