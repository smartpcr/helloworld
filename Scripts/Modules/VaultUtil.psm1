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
        $credentialFolder = "$ScriptFolder\credential"
        New-Item -Path $credentialFolder -ItemType Directory -Force
        $defaultPolicyFile = "$credentialFolder\default_policy.json"
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