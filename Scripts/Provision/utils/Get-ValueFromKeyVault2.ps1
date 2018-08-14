[string]$jsonpayload = [Console]::In.ReadLine()
$json = $jsonpayload | ConvertFrom-Json

$ServicePrincipalAppId = $json.ServicePrincipalAppId
$CertThumbprint = $json.CertThumbprint
$TenantId = $json.TenantId
$VaultName = $json.VaultName
$Name = $json.Name

if (az account show) {
    Write-Host "Already logged in"
}
else {
    az login --service-principal -u "http://$spnName" -p $privateKeyFilePath --tenant $TenantId
}

Login-AzureRmAccount `
    -TenantId $TenantId `
    -ServicePrincipal `
    -CertificateThumbprint $CertThumbprint `
    -ApplicationId $ServicePrincipalAppId | Out-Null

$secret = Get-AzureKeyVaultSecret -VaultName $VaultName -Name $Name
$secretValue = $secret.SecretValueText

Write-Output "{ ""app_secret"": ""$secretValue"" }"