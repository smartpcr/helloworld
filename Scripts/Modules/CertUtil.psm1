
function New-CertificateAsSecret {
    param(
        [string] $CertName,
        [string] $VaultName 
    )

    $cert = New-SelfSignedCertificate `
        -CertStoreLocation "cert:\CurrentUser\My" `
        -Subject "CN=$CertName" `
        -KeySpec KeyExchange `
        -HashAlgorithm "SHA256" `
        -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
    $certPwdSecretName = "$CertName-pwd"
    $spCertPwdSecret = Get-OrCreatePasswordInVault -vaultName $VaultName -secretName $certPwdSecretName
    $pwd = $spCertPwdSecret.SecretValue
    $pfxFilePath = [System.IO.Path]::GetTempFileName() 
    Export-PfxCertificate -cert $cert -FilePath $pfxFilePath -Password $pwd -ErrorAction Stop | Out-Null
    $Bytes = [System.IO.File]::ReadAllBytes($pfxFilePath)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $JSONBlob = @{
        data     = $Base64
        dataType = 'pfx'
        password = $spCertPwdSecret.SecretValueText
    } | ConvertTo-Json
    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($JSONBlob)
    $Content = [System.Convert]::ToBase64String($ContentBytes)
    $SecretValue = ConvertTo-SecureString -String $Content -AsPlainText -Force
    Set-AzureKeyVaultSecret -VaultName $VaultName -Name $CertName -SecretValue $SecretValue | Out-Null

    Remove-Item $pfxFilePath
    Remove-Item "cert:\\CurrentUser\My\$($cert.Thumbprint)"

    return $cert
}

function New-CertificateAsSecret2 {
    param(
        [string] $CertName,
        [string] $VaultName 
    )

    $cert = New-SelfSignedCertificate `
        -CertStoreLocation "cert:\CurrentUser\My" `
        -Subject "CN=$CertName" `
        -KeySpec KeyExchange `
        -HashAlgorithm "SHA256" `
        -Provider "Microsoft Enhanced RSA and AES Cryptographic Provider"
    $certPwdSecretName = "$CertName-pwd"
    $spCertPwdSecret = Get-OrCreatePasswordInVault2 -vaultName $VaultName -secretName $certPwdSecretName
    $pwd = $spCertPwdSecret.value
    $pfxFilePath = [System.IO.Path]::GetTempFileName() 
    Export-PfxCertificate -cert $cert -FilePath $pfxFilePath -Password $pwd -ErrorAction Stop | Out-Null
    $Bytes = [System.IO.File]::ReadAllBytes($pfxFilePath)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    $JSONBlob = @{
        data     = $Base64
        dataType = 'pfx'
        password = ($pwd | ConvertTo-SecureString -AsPlainText -Force)
    } | ConvertTo-Json
    $ContentBytes = [System.Text.Encoding]::UTF8.GetBytes($JSONBlob)
    $Content = [System.Convert]::ToBase64String($ContentBytes)
    $SecretValue = ConvertTo-SecureString -String $Content -AsPlainText -Force
    Set-AzureKeyVaultSecret -VaultName $VaultName -Name $CertName -SecretValue $SecretValue | Out-Null

    Remove-Item $pfxFilePath
    Remove-Item "cert:\\CurrentUser\My\$($cert.Thumbprint)"

    return $cert
}

function Install-CertFromVaultSecret {
    param(
        [string] $VaultName,
        [string] $CertSecretName 
    )
    $certSecret = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $CertSecretName 

    $kvSecretBytes = [System.Convert]::FromBase64String($certSecret.SecretValueText)
    $certDataJson = [System.Text.Encoding]::UTF8.GetString($kvSecretBytes) | ConvertFrom-Json
    $pfxBytes = [System.Convert]::FromBase64String($certDataJson.data)
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bxor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
    $pfx = new-object System.Security.Cryptography.X509Certificates.X509Certificate2

    $certPwdSecretName = "$CertSecretName-pwd"
    $certPwdSecret = Get-OrCreatePasswordInVault -vaultName $VaultName -secretName $certPwdSecretName

    $pfx.Import($pfxBytes, $certPwdSecret.SecretValue, $flags)
    $thumbprint = $pfx.Thumbprint

    $certAlreadyExists = Test-Path Cert:\CurrentUser\My\$thumbprint
    if (!$certAlreadyExists) {
        $x509Store = new-object System.Security.Cryptography.X509Certificates.X509Store -ArgumentList My, CurrentUser
        $x509Store.Open('ReadWrite')
        $x509Store.Add($pfx)
    }

    return $pfx 
}