
function SetupGlobalEnvironmentVariables() {
    param(
        [string] $ScriptFolder
    )

    $ErrorActionPreference = "Stop"
    $scriptFolderName = [System.IO.Path]::GetDirectoryName($ScriptFolder)
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
    param([string] $Message)

    if (-not (Test-Path $env:LogFile)) {
        New-Item -Path $env:LogFile -ItemType File -Force | Out-Null
    }

    $timeString = (Get-Date).ToString("yyyy-MM-dd-HHmmss");
    $formattedMessage = "$timeString $Message" + [System.Environment]::NewLine
    Add-Content -Path $env:LogFile -Value $Message $formattedMessage
}

function LogInfo() {
    param(
        [string] $Message,
        [int] $IndentLevel = 1
    )

    $formatedMessage = $Message
    for ($i = 0; $i -lt $IndentLevel; $i++) {
        $formatedMessage = "`t" + $formatedMessage
    }
    LogVerbose -Message $formatedMessage

    $timeString = (Get-Date).ToString("yyyy-MM-dd-HHmmss");
    Write-Host "$timeString $formatedMessage" -ForegroundColor Yellow
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

function Get-OrCreateServicePrincipalUsingPassword2 {
    param(
        [string] $ServicePrincipalName,
        [string] $ServicePrincipalPwdSecretName,
        [string] $VaultName,
        [string] $ScriptFolder,
        [string] $EnvName
    )

    $servicePrincipalPwd = Get-OrCreatePasswordInVault2 -VaultName $VaultName -secretName $ServicePrincipalPwdSecretName
    $spFound = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    if ($spFound) {
        az ad sp credential reset --name $ServicePrincipalName --password $servicePrincipalPwd.value 
        return $sp
    }

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $ScriptFolder

    $rgName = $bootstrapValues.global.resourceGroup
    $azAccount = az account show | ConvertFrom-Json
    $subscriptionId = $azAccount.id
    $scopes = "/subscriptions/$subscriptionId/resourceGroups/$($rgName)"
    
    LogInfo -Message "Granting spn '$ServicePrincipalName' 'Contributor' role to resource group '$rgName'"
    az ad sp create-for-rbac `
        --name $ServicePrincipalName `
        --password $($servicePrincipalPwd.value) `
        --role="Contributor" `
        --scopes=$scopes | Out-Null
    
    $sp = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    return $sp 
}


function LoginAzureAsUser2 {
    param (
        [string] $SubscriptionName
    )
    
    $azAccount = az account show | ConvertFrom-Json
    if ($null -eq $azAccount -or $azAccount.name -ine $SubscriptionName) {
        az login | Out-Null
        az account set --subscription $SubscriptionName 
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