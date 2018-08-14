
function Test-IsAdmin {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = new-object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    $isAdmin = $prp.IsInRole($adm)
    return $isAdmin
}

<#
    It assumes service principal has unique display name in current directory
    When service principal is already created, return it directly
    Otherwise create a service principal and protect it with certificate.
    key vault is required to store BOTH cert and cert password
    1) a self-signed cert is created and added to key vault. Certificate secret name is 
    the same as service principal name.
    2) JSON blob of cert is stored as key vault secret, so it can be installed on 
    dev box or build agent.
    3) Service principal is created by specifying name and cert credential
#>
function Get-OrCreateServicePrincipalUsingCert {
    param(
        [string] $ServicePrincipalName,
        [string] $VaultName,
        [string] $ScriptFolder,
        [string] $EnvName
    )

    $sp = Get-AzureRmADServicePrincipal -SearchString $ServicePrincipalName | Where-Object { $_.DisplayName -ieq $ServicePrincipalName }
    if ($sp -and $sp -is [array] -and ([array]$sp).Count -ne 1) {
        throw "There are more than one service principal with the same name: '$ServicePrincipalName'"
    }
    if ($sp) {
        return $sp;
    }

    $cert = New-CertificateAsSecret -certName $ServicePrincipalName -vaultName $VaultName
    # write to values.yaml
    $devValueYamlFile = "$ScriptFolder\$EnvName\values.yaml"
    $values = Get-Content $devValueYamlFile -Raw | ConvertFrom-Yaml
    $values.servicePrincipalCertThumbprint = $cert.Thumbprint
    $values | ConvertTo-Yaml | Out-File $devValueYamlFile -Encoding utf8
    
    $certValueWithoutPrivateKey = [System.Convert]::ToBase64String($cert.GetRawCertData())
        
    $sp = New-AzureRMADServicePrincipal `
        -DisplayName $ServicePrincipalName `
        -CertValue $certValueWithoutPrivateKey `
        -EndDate $cert.NotAfter `
        -StartDate $cert.NotBefore

    $values.servicePrincipalAppId = $sp.ApplicationId
    $values | ConvertTo-Yaml | Out-File $devValueYamlFile -Encoding utf8
      
    $completeCertData = [System.Convert]::ToBase64String($cert.Export("Pkcs12"))
    Import-AzureKeyVaultCertificate -VaultName $VaultName -Name "$ServicePrincipalName-cert" -CertificateString $completeCertData | Out-Null

    Set-AzureKeyVaultSecret `
        -VaultName $VaultName `
        -Name "$ServicePrincipalName-appId" `
        -SecretValue ($sp.ApplicationId.ToString() | ConvertTo-SecureString -AsPlainText -Force) | Out-Null

    return $sp
    
}

function Get-OrCreateServicePrincipalUsingPassword {
    param(
        [string] $ServicePrincipalName,
        [string] $ServicePrincipalPwdSecretName,
        [string] $VaultName,
        [string] $ScriptFolder,
        [string] $EnvName
    )

    $sp = Get-AzureRmADServicePrincipal -SearchString $ServicePrincipalName | Where-Object { $_.DisplayName -ieq $ServicePrincipalName }
    if ($sp -and $sp -is [array] -and ([array]$sp).Count -ne 1) {
        throw "There are more than one service principal with the same name: '$ServicePrincipalName'"
    }
    if ($sp) {
        return $sp;
    }

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $ScriptFolder

    $rmContext = LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName
    $rgName = $bootstrapValues.global.resourceGroup
    $scopes = "/subscriptions/$($rmContext.Subscription.Id)/resourceGroups/$($rgName)"
    
    $servicePrincipalPwd = Get-OrCreatePasswordInVault -VaultName $VaultName -secretName $ServicePrincipalPwdSecretName
    $sp = "$(az ad sp create-for-rbac --name $ServicePrincipalName --password $($servicePrincipalPwd.SecretValueText) --role=""Contributor"" --scopes=""$scopes"")"
    
    $sp = Get-AzureRmADServicePrincipal -SearchString $ServicePrincipalName | Where-Object { $_.DisplayName -ieq $ServicePrincipalName }
    return $sp 
}

function Grant-ServicePrincipalPermissions {
    param(
        [string] $servicePrincipalId,
        [string] $subscriptionId,
        [string] $resourceGroupName,
        [string] $VaultName
    )

    $roleAssignment = $null 
    if ($resourceGroupName) {
        $roleAssignment = Get-AzureRmRoleAssignment -ObjectId $servicePrincipalId -ResourceGroupName $resourceGroupName -RoleDefinitionName Contributor 
    }
    else {
        $roleAssignment = Get-AzureRmRoleAssignment -ObjectId $servicePrincipalId -Scope "/subscriptions/$subscriptionId" -RoleDefinitionName Contributor 
    }
    
    if (!$roleAssignment) {
        if ($resourceGroupName) {
            $roleAssignment = New-AzureRmRoleAssignment -ObjectId $ServicePrincipalId -ResourceGroupName $resourceGroupName -RoleDefinitionName Contributor 
        }
        else {
            $roleAssignment = New-AzureRmRoleAssignment -ObjectId $ServicePrincipalId -Scope "/subscriptions/$subscriptionId" -RoleDefinitionName Contributor 
        }
    }

    if ($VaultName) {
        Set-AzureRmKeyVaultAccessPolicy -VaultName $VaultName -ObjectId $servicePrincipalId -PermissionsToSecrets get, list, set, delete
        Set-AzureRmKeyVaultAccessPolicy -VaultName $VaultName -ObjectId $servicePrincipalId -PermissionsToCertificates get, list, update, delete 
    }
}

function Get-OrCreatePasswordInVault { 
    param(
        [string] $VaultName, 
        [string] $secretName
    )

    $res = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $secretName -ErrorAction Ignore
    if ($res) {
        return $res
    }

    $prng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $bytes = New-Object Byte[] 30
    $prng.GetBytes($bytes)
    $password = [System.Convert]::ToBase64String($bytes) + "!@1wW" #  ensure we meet password requirements
    $passwordSecureString = ConvertTo-SecureString -String $password -AsPlainText -Force
    return Set-AzureKeyVaultSecret `
        -VaultName $VaultName `
        -Name $secretName `
        -SecretValue $passwordSecureString
}

function Get-OrCreateSelfSignedCertificateInVault {
    param(
        [string] $VaultName, 
        [string] $CertificateName, 
        [string] $SubjectName
    ) 

    try {
        # version 2.1 throws, 3.3.1 returns null 
        $res = Get-AzureKeyVaultCertificate -VaultName $VaultName -Name $CertificateName
        if ($res) {
            $currentDate = (Get-Date).ToUniversalTime()
            if (($currentDate -gt $res.Certificate.NotBefore) -and `
                ($currentDate -lt ($res.Certificate.NotAfter.AddDays(-30)))) {
                return $res
            }
        }
    }
    catch {
    }
    
    Write-Verbose "Creating self-signed cert in KV"
    $policy = New-AzureKeyVaultCertificatePolicy -SubjectName $SubjectName -IssuerName Self -ValidityInMonths 12
    Add-AzureKeyVaultCertificate -VaultName $VaultName -Name $certificateName -CertificatePolicy $policy | Out-Null
    while ((Get-AzureKeyVaultCertificateOperation -VaultName $VaultName -Name $CertificateName).Status -ne 'completed') {
        Start-Sleep -Seconds 2
        Write-Verbose "Waiting on Key Vault operation"
    }

    return Get-AzureKeyVaultCertificate -VaultName $VaultName -Name $CertificateName
}

<#
    1) certificate will be installed on cert:\CurrentUser\My
    2) password for cert is randomly generated and stored as key vault secret 
    with $(SerfvicePrincipalName)-pwd
#>
function Connect-ToAzure {
    param (
        [string] $EnvName = "dev",
        [string] $ScriptFolder
    )
    
    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $ScriptFolder
    $thumbprint = $bootstrapValues.global.servicePrincipalCertThumbprint
    $spAppId = $bootstrapValues.global.servicePrincipalAppId

    $needInstallCert = $false 
    if ($null -eq $thumbprint) {
        $needInstallCert = $true
    }
    else {
        $certAlreadyExists = Test-Path Cert:\CurrentUser\My\$thumbprint
        if (!$certAlreadyExists) {
            $needInstallCert = $true 
        }
    }
    if ($needInstallCert) {
        InstallServicePrincipalCert -EnvName $EnvName -ScriptFolder $ScriptFolder
    }

    Login-AzureRmAccount `
        -TenantId $bootstrapValues.global.tenantId `
        -ServicePrincipal `
        -CertificateThumbprint $thumbprint `
        -ApplicationId $spAppId
}

function InstallServicePrincipalCert {
    param (
        [string] $EnvName = "dev",
        [string] $ScriptFolder
    )

    $bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -ScriptFolder $ScriptFolder
    $spnName = $bootstrapValues.global.servicePrincipal
    $vaultName = $bootstrapValues.kv.name

    # ensure logged in 
    LoginAzureAsUser -SubscriptionName $bootstrapValues.global.subscriptionName

    Install-CertFromVaultSecret -VaultName $vaultName -CertSecretName $spnName 
}

function Test-NetCoreInstalled () {
    try {
        $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
        $isInstalled = $false
        if ($dotnetCmd) {
            $isInstalled = Test-Path($dotnetCmd.Source)
        }
        return $isInstalled
    }
    catch {
        return $false 
    }
}

function Test-AzureCliInstalled() {
    try {
        $azCmd = Get-Command az -ErrorAction SilentlyContinue
        if ($azCmd) {
            return Test-Path $azCmd.Source 
        }
    }
    catch {}
    return $false 
}

function Test-ChocoInstalled() {
    try {
        $chocoVersion = Invoke-Expression "choco -v" -ErrorAction SilentlyContinue
        return ($chocoVersion -ne $null)
    }
    catch {}
    return $false 
}

function Test-DockerInstalled() {
    try {
        $dockerVer = Invoke-Expression "docker --version" -ErrorAction SilentlyContinue
        return ($dockerVer -ne $null)
    }
    catch {}
    return $false 
}

function LoginAzureAsUser {
    param (
        [string] $SubscriptionName
    )
    
    $rmContext = Get-AzureRmContext
    if (!$rmContext -or $rmContext.Subscription.Name -ne $SubscriptionName) {
        Login-AzureRmAccount | Out-Null
        Set-AzureRmContext -Subscription $SubscriptionName | Out-Null
        $rmContext = Get-AzureRmContext
    }

    return $rmContext
}

<# there is bug filtering and test vm offering, manually set vmSize for different region #>
function Test-VMSize {
    param(
        [string] $VMSize,
        [string] $Location
    )

    $vmSizeFound = "$(az vm list-sizes -l $Location --query ""[?name=='$VMSize']"")"
    if ($vmSizeFound) {
        return $true 
    }
    return $false 
}
