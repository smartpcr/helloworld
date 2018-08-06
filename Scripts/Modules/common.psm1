function Test-IsAdmin {
    $wid = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $prp = new-object System.Security.Principal.WindowsPrincipal($wid)
    $adm = [System.Security.Principal.WindowsBuiltInRole]::Administrator
    $isAdmin = $prp.IsInRole($adm)
    return $isAdmin
}

function Copy-YamlObject {
    param (
        [object] $fromObj,
        [object] $toObj
    )
    
    $fromObj.Keys | ForEach-Object {
        $name = $_ 
        $value = $fromObj.Item($name)
    
        if ($value) {
            $tgtName = $toObj.Keys | Where-Object { $_ -eq $name }
            if (!$tgtName) {
                Write-Host "Adding $($name) to terget object"
                $toObj.Add($name, $value)
            }
            else {
                Write-Host "Overwrite prop: name=$($name), value=$($value)"
                $tgtValue = $toObj.Item($tgtName)
                if ($value -is [string] -or $value -is [int] -or $value -is [bool]) {
                    if ($value -ne $tgtValue) {
                        Write-Host "Change value from $($tgtValue) to $($value)"
                        $toObj[$tgtName] = $value
                    }
                }
                else {
                    Write-Host "Copy object $($name)"
                    Copy-YamlObject -fromObj $value -toObj $tgtValue
                }
            }
        }
    }
}

function Set-Values {
    param (
        [object] $valueTemplate,
        [object] $settings
    )

    $regex = New-Object System.Text.RegularExpressions.Regex("\{\{\s*\.Values\.(\w+)\s*\}\}")
    $match = $regex.Match($valueTemplate)
    while ($match.Success) {
        $toBeReplaced = $match.Value
        $searchKey = $match.Groups[1].Value
        $found = $settings.Keys | Where-Object { $_ -eq $searchKey }
        if ($found) {
            $replaceValue = $settings.Item($found)
            Write-Host "Replace $toBeReplaced with $replaceValue"
            $valueTemplate = ([string]$valueTemplate).Replace($toBeReplaced, $replaceValue)
            $match = $regex.Match($valueTemplate)
        }
        else {
            $match = $match.NextMatch()
        }
    }

    return $valueTemplate
}

function New-CertificateAsSecret {
    param(
        [string] $certName,
        [string] $VaultName 
    )

    $cert = New-SelfSignedCertificate `
        -CertStoreLocation "cert:\CurrentUser\My" `
        -Subject "CN=$certName" `
        -KeySpec KeyExchange `
        -HashAlgorithm "SHA256" `
        -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
    $certPwdSecretName = "$certName-pwd"
    $spCertPwdSecret = Get-OrCreatePasswordInVault -vaultName $VaultName -secretName $certPwdSecretName
    $pwd = $spCertPwdSecret.SecretValue
    $pfxFilePath = [System.IO.Path]::GetTempFileName()
    Export-PfxCertificate -cert $cert -FilePath $pfxFilePath -Password $pwd -ErrorAction Stop
    $Bytes = [System.IO.File]::ReadAllBytes($pfxFilePath)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $JSONBlob = @{
        data     = $Base64
        dataType = 'pfx'
        password = $Password
    } | ConvertTo-Json
    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($JSONBlob)
    $Content = [System.Convert]::ToBase64String($ContentBytes)
    $SecretValue = ConvertTo-SecureString -String $Content -AsPlainText -Force
    Set-AzureKeyVaultSecret -VaultName $VaultName -Name $certName -SecretValue $SecretValue -Verbose

    Remove-Item $pfxFilePath
    Remove-Item "cert:\\CurrentUser\My\$($cert.Thumbprint)"

    return $cert
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
function Get-OrCreateServicePrincipal {
    param(
        [string] $servicePrincipalName,
        [string] $VaultName 
    )

    $sp = Get-AzureRmADServicePrincipal -SearchString $servicePrincipalName | Where-Object { $_.DisplayName -ieq $servicePrincipalName }
    if ($sp -and $sp -is [array] -and ([array]$sp).Count -ne 1) {
        throw "There are more than one service principal with the same name: '$servicePrincipalName'"
    }
    if ($sp) {
        return $sp;
    }

    $cert = New-CertificateAsSecret -certName $servicePrincipalName -vaultName $VaultName

    try {
        $certValueWithoutPrivateKey = [System.Convert]::ToBase64String($cert.GetRawCertData())
    
        $sp = New-AzureRMADServicePrincipal `
            -DisplayName $servicePrincipalName `
            -CertValue $certValueWithoutPrivateKey `
            -EndDate $cert.NotAfter `
            -StartDate $cert.NotBefore
      
        $completeCertData = [System.Convert]::ToBase64String($cert.Export("Pkcs12"))

        Import-AzureKeyVaultCertificate -VaultName $VaultName -Name "$servicePrincipalName-cert" -CertificateString $completeCertData

        Set-AzureKeyVaultSecret `
            -VaultName $VaultName `
            -Name "$servicePrincipalName-appId" `
            -SecretValue ($sp.ApplicationId.ToString() | ConvertTo-SecureString -AsPlainText -Force)

        return $sp
    }
    finally {
        Remove-Item "cert:\\CurrentUser\My\$($cert.Thumbprint)"
    }
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

function Get-EnvironmentSettings {
    param(
        [string] $EnvName = "dev",
        [string] $ScriptFolder
    )
    
    Install-Module powershell-yaml
    

    $values = Get-Content "$ScriptFolder\values.yaml" -Raw | ConvertFrom-Yaml
    if ($EnvName) {
        $envValueYamlFile = "$ScriptFolder\$EnvName\values.yaml"
        if (Test-Path $envValueYamlFile) {
            $envValues = Get-Content $envValueYamlFile -Raw | ConvertFrom-Yaml
            Copy-YamlObject -fromObj $envValues -toObj $values
        }
    }

    $bootstrapTemplate = Get-Content "$ScriptFolder\bootstrap.yaml" -Raw
    $bootstrapTemplate = Set-Values -valueTemplate $bootstrapTemplate -settings $values
    $bootstrapValues = $bootstrapTemplate | ConvertFrom-Yaml

    return $bootstrapValues
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
    
    $bootstrapValues = Get-EnvironmentSettings -envName $EnvName -ScriptFolder $ScriptFolder
    $spnName = $bootstrapValues.global.servicePrincipal
    $vaultName = $bootstrapValues.global.keyVault

    # cert must be also available from kv secret as json blob
    $certSecret = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $spnName 

    $kvSecretBytes = [System.Convert]::FromBase64String($certSecret.SecretValueText)
    $certDataJson = [System.Text.Encoding]::UTF8.GetString($kvSecretBytes) | ConvertFrom-Json
    $pfxBytes = [System.Convert]::FromBase64String($certDataJson.data)
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bxor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
    $pfx = new-object System.Security.Cryptography.X509Certificates.X509Certificate2
    $pfx.Import($pfxBytes, $null, $flags)
    $thumbprint = $pfx.Thumbprint

    $certAlreadyExists = Test-Path Cert:\CurrentUser\My\$thumbprint
    if (!$certAlreadyExists) {
        $x509Store = new-object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList My, CurrentUser
        $x509Store.Open('ReadWrite')
        $x509Store.Add($pfx)
    }

    $spAppId = (Get-AzureKeyVaultSecret -VaultName $vaultName -Name "$($spnName)-appId").SecretValueText

    $spn = Get-AzureRmADServicePrincipal | Where-Object { $_.DisplayName -eq $spnName }

    Login-AzureRmAccount `
        -TenantId $bootstrapValues.global.tenantId `
        -ServicePrincipal `
        -CertificateThumbprint $thumbprint `
        -ApplicationId $spAppId
}

function isNetCoreInstalled () {
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

function isAzureCliInstalled() {
    try {
        $azCmd = Get-Command az -ErrorAction SilentlyContinue
        if ($azCmd) {
            return Test-Path $azCmd.Source 
        }
    }
    catch {}
    return $false 
}

function isChocoInstalled() {
    try {
        $chocoVersion = Invoke-Expression "choco -v" -ErrorAction SilentlyContinue
        return ($chocoVersion -ne $null)
    }
    catch {}
    return $false 
}

function isDockerInstalled() {
    try {
        $chocoVersion = Invoke-Expression "docker --version" -ErrorAction SilentlyContinue
        return ($chocoVersion -ne $null)
    }
    catch {}
    return $false 
}
