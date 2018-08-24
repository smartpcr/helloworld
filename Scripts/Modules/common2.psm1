
function SetupGlobalEnvironmentVariables() {
    param(
        [string] $ScriptFolder
    )

    $ErrorActionPreference = "Stop"
    $scriptFolderName = Split-Path $ScriptFolder -Leaf
    if ($null -eq $scriptFolderName -or $scriptFolderName -ne "Scripts") {
        throw "Invalid script folder: '$ScriptFolder'"
    }
    $logFolder = Join-Path $ScriptFolder "log"
    New-Item -Path $logFolder -ItemType Directory -Force | Out-Null
    $timeString = (Get-Date).ToString("yyyy-MM-dd-HHmmss")
    $logFile = Join-Path $logFolder "$($timeString).log"
    $env:LogFile = $logFile
}

function LogVerbose() {
    param(
        [string] $Message,
        [int] $IndentLevel = 0)

    if (-not (Test-Path $env:LogFile)) {
        New-Item -Path $env:LogFile -ItemType File -Force | Out-Null
    }

    $timeString = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $formatedMessage = ""
    for ($i = 0; $i -lt $IndentLevel; $i++) {
        $formatedMessage = "`t" + $formatedMessage
    }
    $formatedMessage += "$timeString $Message"
    Add-Content -Path $env:LogFile -Value $formatedMessage
}

function LogInfo() {
    param(
        [string] $Message,
        [int] $IndentLevel = 1
    )

    $formatedMessage = ""
    for ($i = 0; $i -lt $IndentLevel; $i++) {
        $formatedMessage = "`t" + $formatedMessage
    }
    $formatedMessage += $Message
    LogVerbose -Message $formatedMessage -IndentLevel $IndentLevel

    Write-Host $formatedMessage -ForegroundColor Yellow
}

function LogTitle() {
    param(
        [string] $Message
    )

    Write-Host "`n"
    Write-Host "`t`t***** $Message *****" -ForegroundColor Green
    Write-Host "`n"
}

function LogStep() {
    param(
        [string] $Message,
        [int] $Step
    )

    $formatedMessage = "$Step) $Message"
    LogVerbose -Message $formatedMessage
    Write-Host "$formatedMessage" -ForegroundColor Green
}

function Get-OrCreatePasswordInVault2 { 
    param(
        [string] $VaultName, 
        [string] $SecretName
    )

    $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    if ($res) {
        return $res
    }

    $prng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $bytes = New-Object Byte[] 30
    $prng.GetBytes($bytes)
    $password = [System.Convert]::ToBase64String($bytes) + "!@1wW" #  ensure we meet password requirements
    az keyvault secret set --vault-name $VaultName --name $SecretName --value $password
    $res = az keyvault secret show --vault-name $VaultName --name $SecretName | ConvertFrom-Json
    return $res 
}

function Get-OrCreateAksServicePrincipal {
    param(
        [string] $ServicePrincipalName,
        [string] $ServicePrincipalPwdSecretName,
        [string] $VaultName,
        [string] $EnvRootFolder,
        [string] $EnvName
    )

    $servicePrincipalPwd = Get-OrCreatePasswordInVault2 -VaultName $VaultName -secretName $ServicePrincipalPwdSecretName
    $spFound = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    if ($spFound) {
        az ad sp credential reset --name $ServicePrincipalName --password $servicePrincipalPwd.value 
        return $sp
    }

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $EnvRootFolder
    $rgName = $bootstrapValues.aks.resourceGroup
    $azAccount = az account show | ConvertFrom-Json
    $subscriptionId = $azAccount.id
    $scopes = "/subscriptions/$subscriptionId/resourceGroups/$($rgName)"
    $currentEnvFolder = Join-Path $EnvRootFolder $EnvName
    $spnAuthJsonFile = Join-Path $currentEnvFolder "aks-spn-auth.json"
    
    LogInfo -Message "Granting spn '$ServicePrincipalName' 'Contributor' role to resource group '$rgName'"
    az ad sp create-for-rbac `
        --name $ServicePrincipalName `
        --password $($servicePrincipalPwd.value) `
        --identifier-uris "http://$ServicePrincipalName" `
        --role="Contributor" `
        --scopes=$scopes `
        --required-resource-accesses $spnAuthJsonFile | Out-Null
    
    $sp = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json

    LogInfo -Message "Grant required resource access for aad app..."
    az ad app update --id $sp.appId --required-resource-accesses $spnAuthJsonFile | Out-Null
    return $sp 
}


function Get-OrCreateAksClientApp {
    param(
        [string] $EnvRootFolder,
        [string] $EnvName
    )

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $EnvRootFolder
    $ClientAppName = $bootstrapValues.aks.clientAppName
    $ClientAppPwdSecretName = $bootstrapValues.aks.clientAppPassword
    $VaultName = $bootstrapValues.kv.name

    $aksSpn = az ad sp list --display-name $bootstrapValues.aks.servicePrincipal | ConvertFrom-Json
    if (!$aksSpn) {
        throw "Cannot create client app when server app with name '$($bootstrapValues.aks.servicePrincipal)' is not found!"
    }

    $servicePrincipalPwd = Get-OrCreatePasswordInVault2 -VaultName $VaultName -secretName $ClientAppPwdSecretName
    $spFound = az ad app list --display-name $ClientAppName | ConvertFrom-Json
    if ($spFound -and $spFound -is [array]) {
        if ([array]$spFound.Count -gt 1) {
            throw "Duplicated client app found for '$ClientAppName'"
        }
    }
    if ($spFound) {
        az ad sp credential reset --name $ClientAppName --password $servicePrincipalPwd.value 
        return $sp
    }
    
    LogInfo -Message "Granting client app '$ClientAppName' and grant access to server app '$($bootstrapValues.aks.servicePrincipal)'"
    $resourceAccess = "[{`"resourceAccess`": [{`"id`": `"318f4279-a6d6-497a-8c69-a793bda0d54f`", `"type`": `"Scope`"}],`"resourceAppId`": `"$($aksSpn.appId)`"}]" 
    $currentEnvFolder = Join-Path $EnvRootFolder $EnvName
    $clientAppResourceAccessJsonFile = Join-Path $currentEnvFolder "aks-client-auth.json"
    $resourceAccess | Out-File $clientAppResourceAccessJsonFile -Encoding ascii

    az ad app create `
        --display-name $ClientAppName `
        --native-app `
        --required-resource-accesses @$clientAppResourceAccessJsonFile | Out-Null
    
    $sp = az ad sp list --display-name $ClientAppName | ConvertFrom-Json
    return $sp 
}

function LoginAzureAsUser2 {
    param (
        [string] $SubscriptionName
    )
    
    $azAccount = az account show | ConvertFrom-Json
    if ($null -eq $azAccount -or $azAccount.name -ine $SubscriptionName) {
        az login | Out-Null
        az account set --subscription $SubscriptionName | Out-Null
    }

    $currentAccount = az account show | ConvertFrom-Json
    return $currentAccount
}

function LoginAsServicePrincipal {
    param (
        [string] $EnvName = "dev",
        [string] $ScriptFolder
    )
    
    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $ScriptFolder
    $vaultName = $bootstrapValues.kv.name
    $spnName = $bootstrapValues.global.servicePrincipal
    $certName = $spnName
    $tenantId = $bootstrapValues.global.tenantId

    $privateKeyFilePath = "$ScriptFolder/credential/$certName.key"
    if (-not (Test-Path $privateKeyFilePath)) {
        LoginAzureAsUser2 -SubscriptionName $bootstrapValues.global.subscriptionName
        DownloadCertFromKeyVault -VaultName $vaultName -CertName $certName -ScriptFolder $ScriptFolder
    }
    
    LogInfo -Message "Login as service principal '$spnName'"
    az login --service-principal -u "http://$spnName" -p $privateKeyFilePath --tenant $tenantId | Out-Null
}