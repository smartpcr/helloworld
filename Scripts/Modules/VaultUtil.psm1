function EnsureCertificateInKeyVault {
    param(
        [string] $VaultName,
        [string] $CertName,
        [string] $ScriptFolder
    )

    $existingCert = az keyvault certificate list --vault-name $VaultName --query "[?id=='https://$VaultName.vault.azure.net/certificates/$CertName']" | ConvertFrom-Json
    if ($existingCert) {
        Write-Host "Certificate '$CertName' already exists in vault '$VaultName'"
    }
    else {
        $credentialFolder = Join-Path $ScriptFolder "credential"
        New-Item -Path $credentialFolder -ItemType Directory -Force
        $defaultPolicyFile = Join-Path $credentialFolder "default_policy.json"
        az keyvault certificate get-default-policy -o json | Out-File $defaultPolicyFile -Encoding utf8 
        az keyvault certificate create -n $CertName --vault-name $vaultName -p @$defaultPolicyFile
    }
}

function DownloadCertFromKeyVault {
    param(
        [string] $VaultName,
        [string] $CertName,
        [string] $ScriptFolder
    )

    $credentialFolder = Join-Path $ScriptFolder "credential"
    New-Item -Path $credentialFolder -ItemType Directory -Force
    $pfxCertFile = Join-Path $credentialFolder "$certName.pfx"
    $pemCertFile = Join-Path $credentialFolder "$certName.pem"
    $keyCertFile = Join-Path $credentialFolder "$certName.key"

    az keyvault secret download --vault-name $VaultName -n $CertName -e base64 -f $pfxCertFile
    openssl pkcs12 -in $pfxCertFile -clcerts -nodes -out $keyCertFile -passin pass:
    openssl rsa -in $keyCertFile -out $pemCertFile
}

function EnsureSshCert {
    param(
        [string] $VaultName,
        [string] $CertName,
        [string] $EnvName,
        [string] $ScriptFolder
    )

    $EnvFolder = Join-Path $ScriptFolder "Env"
    $credentialFolder = Join-Path (Join-Path $EnvFolder $EnvName) "credential"
    $certFile = Join-Path $credentialFolder $CertName
    if (-not (Test-Path $certFile)) {
        $certSecret = az keyvault secret show --vault-name $VaultName --name $CertName | ConvertFrom-Json
        if (!$certSecret) {
            $pubCertName = "$($CertName)-pub"
            $pwdName = "$($CertName)-pwd"
            $pubCertFile = Join-Path $credentialFolder $pubCertName
        
            $pwdSecret = Get-OrCreatePasswordInVault2 -VaultName $VaultName -SecretName $pwdName
            ssh-keygen -f $certFile -P $pwdSecret.value 
            $certPemString = ssh-keygen -f $certFile -e -m pem 
            $certPemString | Out-File $pubCertFile

            $certPublicString = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($pubCertFile))
            az keyvault secret set --vault-name $VaultName --name $CertName --value $certPublicString
            $certPrivateString = [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($certFile))
            az keyvault secret set --vault-name $VaultName --name $pubCertName --value $certPrivateString
        }
    }
}