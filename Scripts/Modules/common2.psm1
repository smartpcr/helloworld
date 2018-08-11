$env:out_null = "[?n]|[0]"

function LoginAzureAsUser2 {
    param (
        [string] $SubscriptionName
    )
    
    $currentAccount = az account show | ConvertFrom-Json
    if ($currentAccount -and $currentAccount.name -eq $SubscriptionName) {
        return $currentAccount
    }

    az login --query $env:out_null
    az account set --subscription $SubscriptionName --query $env:out_null
    $currentAccount = az account show | ConvertFrom-Json
    return $currentAccount
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
function Get-OrCreateServicePrincipalUsingCert2 {
    param(
        [string] $ServicePrincipalName,
        [string] $VaultName,
        [string] $ScriptFolder,
        [string] $EnvName
    )

    $spsFound = az ad sp list --display-name $ServicePrincipalName | ConvertFrom-Json
    if ($spsFound -and $spsFound.Count -eq 1) {
        return $spsFound[0];
    }

    if ($spsFound -and $spsFound.Count -ne 1) {
        throw "There are more than one service principal with the same name: '$ServicePrincipalName'"
    }

    $certName = $ServicePrincipalName
    $cert = New-CertificateAsSecret2 -certName $certName -vaultName $VaultName
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


function Get-OrCreatePasswordInVault2 { 
    param(
        [string] $VaultName, 
        [string] $secretName
    )

    $res = az keyvault secret show --vault-name $VaultName --name $secretName | ConvertFrom-Json
    if ($res) {
        return $res
    }

    $prng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    $bytes = New-Object Byte[] 30
    $prng.GetBytes($bytes)
    $password = [System.Convert]::ToBase64String($bytes) + "!@1wW" #  ensure we meet password requirements
    $res = az keyvault secret set --vault-name $VaultName --name $secretName --value $password
    return $res 
}
