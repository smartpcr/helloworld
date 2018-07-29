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

function Get-OrCreateCertificateInKeyVault {
    param(
        [string] $certName,
        [string] $vaultName
    )

    $policy = Get-AzureKeyVaultCertificatePolicy -VaultName $vaultName -Name $certName -ErrorAction SilentlyContinue
    if (!$policy) {
        $policy = New-AzureKeyVaultCertificatePolicy -SubjectName "CN=$certName" -IssuerName Self -ValidityInMonths 12
    }

    $cert = Get-AzureKeyVaultCertificate -VaultName $vaultName -Name $certName -ErrorAction SilentlyContinue
    if (!cert) {
        Add-AzureKeyVaultCertificate -VaultName $bootstrapValues.global.keyVault -Name $certName -CertificatePolicy $policy
    }
    
    return $cert 
}

function Get-OrCreateServicePrincipal {
    param(
        [string] $servicePrincipalName,
        [string] $vaultName 
    )

    $sp = Get-AzureRmADServicePrincipal -SearchString $servicePrincipalName | Where-Object { $_.DisplayName -ieq $servicePrincipalName }
    if ($sp -and $sp -is [array] -and ([array]$sp).Count -ne 1) {
        throw "There are more than one service principal with the same name: '$servicePrincipalName'"
    }

    if (!$sp) {
        $spCertPwdSecretName = "$servicePrincipalName-pwd"
        $spCertPwdSecret = Get-OrCreatePasswordInVault -vaultName $vaultName -secretName $spCertPwdSecretName
        $spCert = Get-OrCreateCertificateInKeyVault -certName $servicePrincipalName -vaultName $vaultName
        $thumbprint = $spCert.Thumbprint
        $pwd = $spCertPwdSecret.SecretValue
        Export-PfxCertificate -cert Cert:\LocalMachine\My\$thumbprint -FilePath "$($spnName).pfx" -Password $pwd

        # TODO: change to use certificate
        New-AzureRmADServicePrincipal `
            -DisplayName $servicePrincipalName `
            -Password $spCertPwdSecret.SecretValueText `
            -StartDate (Get-Date) `
            -EndDate ((Get-Date).AddYears(1))

        $trials = 0
        $sleepIntervalSeconds = 5
        $sp = Get-AzureRmADServicePrincipal -SearchString $servicePrincipalName | Where-Object { $_.DisplayName -ieq $servicePrincipalName }
        while ($sp -eq $null -and $trials -lt 10) {
            Start-Sleep $sleepIntervalSeconds
            $trials++
            $sp = Get-AzureRmADServicePrincipal -SearchString $servicePrincipalName | Where-Object { $_.DisplayName -ieq $servicePrincipalName }
        }
    }

    if ($sp -eq $null) {
        throw "Unable to create service principal with name '$spName'"
    }

    return $sp 
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
            $roleAssignment = New-AzureRmRoleAssignment -ObjectId $ServicePrincipal.Id -ResourceGroupName $resourceGroupName -RoleDefinitionName Contributor 
        }
        else {
            $roleAssignment = New-AzureRmRoleAssignment -ObjectId $ServicePrincipal.Id -Scope "/subscriptions/$subscriptionId" -RoleDefinitionName Contributor 
        }
    }

    if ($VaultName) {
        Set-AzureRmKeyVaultAccessPolicy -VaultName $vaultName -ObjectId $servicePrincipalId -PermissionsToSecrets get, list, set, delete
        Set-AzureRmKeyVaultAccessPolicy -VaultName $vaultName -ObjectId $servicePrincipalId -PermissionsToCertificates get, list, set, delete 
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