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
        [string] $vaultName 
    )

    $cert = New-SelfSignedCertificate `
        -CertStoreLocation "cert:\CurrentUser\My" `
        -Subject "CN=$certName" `
        -KeySpec KeyExchange `
        -HashAlgorithm "SHA256" `
        -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
    $certPwdSecretName = "$certName-pwd"
    $spCertPwdSecret = Get-OrCreatePasswordInVault -vaultName $vaultName -secretName $certPwdSecretName
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
    Set-AzureKeyVaultSecret -VaultName $vaultName -Name $certName -SecretValue $SecretValue -Verbose

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
        [string] $vaultName 
    )

    $sp = Get-AzureRmADServicePrincipal -SearchString $servicePrincipalName | Where-Object { $_.DisplayName -ieq $servicePrincipalName }
    if ($sp -and $sp -is [array] -and ([array]$sp).Count -ne 1) {
        throw "There are more than one service principal with the same name: '$servicePrincipalName'"
    }
    if ($sp) {
        return $sp;
    }

    $cert = New-CertificateAsSecret -certName $servicePrincipalName -vaultName $vaultName

    try {
        $certValueWithoutPrivateKey = [System.Convert]::ToBase64String($cert.GetRawCertData())
    
        $sp = New-AzureRMADServicePrincipal `
            -DisplayName $servicePrincipalName `
            -CertValue $certValueWithoutPrivateKey `
            -EndDate $cert.NotAfter `
            -StartDate $cert.NotBefore
      
        $completeCertData = [System.Convert]::ToBase64String($cert.Export("Pkcs12"))

        Import-AzureKeyVaultCertificate -VaultName $vaultName -Name "$servicePrincipalName-cert" -CertificateString $completeCertData

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
        [string] $vaultName
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
        Set-AzureRmKeyVaultAccessPolicy -VaultName $vaultName -ObjectId $servicePrincipalId -PermissionsToSecrets get, list, set, delete
        Set-AzureRmKeyVaultAccessPolicy -VaultName $vaultName -ObjectId $servicePrincipalId -PermissionsToCertificates get, list, update, delete 
    }
}

function Get-OrCreatePasswordInVault { 
    param(
        [string] $vaultName, 
        [string] $secretName
    )

    $res = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $secretName -ErrorAction Ignore
    if ($res) {
        return $res
    }

    $prng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $bytes = New-Object Byte[] 30
    $prng.GetBytes($bytes)
    $password = [System.Convert]::ToBase64String($bytes) + "!@1wW" #  ensure we meet password requirements
    $passwordSecureString = ConvertTo-SecureString -String $password -AsPlainText -Force
    return Set-AzureKeyVaultSecret `
        -VaultName $vaultName `
        -Name $secretName `
        -SecretValue $passwordSecureString
}

function Get-EnvironmentSettings {
    param(
        [string] $envName = "dev"
    )
    
    $scriptFolder = $PSScriptRoot
    if (!$scriptFolder) {
        $scriptFolder = Get-Location
    }

    Install-Module powershell-yaml
    

    $values = Get-Content "$scriptFolder\values.yaml" -Raw | ConvertFrom-Yaml
    if ($envName) {
        $envValueYamlFile = "$scriptFolder\$envName\values.yaml"
        if (Test-Path $envValueYamlFile) {
            $envValues = Get-Content $envValueYamlFile -Raw | ConvertFrom-Yaml
            Copy-YamlObject -fromObj $envValues -toObj $values
        }
    }

    $bootstrapTemplate = Get-Content "$scriptFolder\bootstrap.yaml" -Raw
    $bootstrapTemplate = Set-Values -valueTemplate $bootstrapTemplate -settings $values
    $bootstrapValues = $bootstrapTemplate | ConvertFrom-Yaml

    return $bootstrapValues
}

function Copy-CertificateAsJson {
    param(
        [string] $SourceVaultName,
        [string] $CertificateName, 
        [string] $DestinationVault
    )
    $unprotectedBytes = [System.Convert]::FromBase64String((Get-AzureKeyVaultSecret -VaultName $SourceVaultName -Name $CertificateName).SecretValueText)
    $cert = new-object system.Security.Cryptography.X509Certificates.X509Certificate2
    $cert.Import($unprotectedBytes, $null, 'Exportable')
    $password = (GetOrCreatePasswordInVault -vaultName $DestinationVault -secretName "$CertificateName-pws").SecretValueText
    $pfxProtectedBytes = $cert.Export('Pkcs12', $password)

    $jsonBlob = @{
        data     = [System.Convert]::ToBase64String($pfxProtectedBytes)
        dataType = 'pfx'
        password = $password
    } | ConvertTo-Json
     
    $contentbytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBlob)
    $content = [System.Convert]::ToBase64String($contentbytes)
    
    $secret = GetOrUpdateSecret -VaultName $DestinationVault -SecretName $CertificateName -SecretValue $content 

    return @{
        certificateUri        = $secret.Id
        certificateThumbprint = $cert.Thumbprint
    }
}

function GetOrUpdateSecret($VaultName, $SecretName, $SecretValue) {
    $res = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $SecretName -ErrorAction Ignore
    if ($res -and ($res.SecretValueText -eq $SecretValue)) {
        return $res
    }

    return Set-AzureKeyVaultSecret -VaultName $VaultName -Name $SecretName -SecretValue (ConvertTo-SecureString -String $SecretValue -AsPlainText -Force)
}

function GetOrCreateSelfSignedCertificateInVault {
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
    Add-AzureKeyVaultCertificate -VaultName $vaultName -Name $certificateName -CertificatePolicy $policy | Out-Null
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
        [string] $envName = "dev"
    )
    
    $bootstrapValues = Get-EnvironmentSettings -envName $envName
    $spnName = $bootstrapValues.global.servicePrincipal
    $vaultName = $bootstrapValues.global.keyVault

    # cert must be also available from kv secret as json blob
    $certSecret = Get-AzureKeyVaultSecret -VaultName $vaultName -Name $spnName 
    $pfxBytes = [System.Convert]::FromBase64String($certSecret.SecretValueText)
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bxor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
    $pfx = new-object System.Security.Cryptography.X509Certificates.X509Certificate2
    $pfx.Import($pfxBytes, $null, $flags)

    $certAlreadyExists = Test-Path Cert:\CurrentUser\My\$($pfx.Thumbprint)
    if (!$certAlreadyExists) {
        $x509Store = new-object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList My, CurrentUser
        $x509Store.Open('ReadWrite')
        $x509Store.Add($pfx)
    }

    $spn = Get-AzureRmADServicePrincipal | Where-Object { $_.DisplayName -eq $spnName }

    Login-AzureRmAccount `
        -TenantId $bootstrapValues.global.tenantId `
        -ServicePrincipal `
        -CertificateThumbprint $pfx.Thumbprint `
        -ApplicationId $spn.ApplicationId
}