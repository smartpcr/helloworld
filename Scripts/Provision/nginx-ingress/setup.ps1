# [Ingress and TLS](https://docs.microsoft.com/en-us/azure/aks/ingress)

param([string] $EnvName = "dev")

$ingressProvisionFolder = $PSScriptRoot
if (!$ingressProvisionFolder) {
    $ingressProvisionFolder = Get-Location
}
$provisionFolder = Split-Path $ingressProvisionFolder -Parent
$scriptFolder = Split-Path $provisionFolder -Parent
$envFolder = Join-Path $scriptFolder "Env"
$moduleFolder = Join-Path $scriptFolder "modules"
Import-Module (Join-Path $moduleFolder "common2.psm1") -Force
Import-Module (Join-Path $moduleFolder "YamlUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "VaultUtil.psm1") -Force
Import-Module (Join-Path $moduleFolder "TerraformUtil.psm1") -Force
SetupGlobalEnvironmentVariables -ScriptFolder $scriptFolder
LogTitle "Setup Nginx Ingress Environment '$EnvName'"
$bootstrapValues = Get-EnvironmentSettings -EnvName $EnvName -EnvRootFolder $envFolder
# variables used in this demo 
$demoNamespace = "ingress-test"
$appName = "demo"
$domainName = "xiaodong.world"
$hostEnvironment = "staging"
$hostName = "$hostEnvironment.$domainName"
$tlsSecret = "$hostEnvironment.$domainName-tls"
$ownerEmail = "lingxd@gmail.com"


LogStep -Step 1 -Message "Install nginx-ingress..."
helm install stable/nginx-ingress --name nginx-ingress --namespace $demoNamespace


LogStep -Step 2 -Message "Retrieving public IP address..."
LogInfo -Message "Note: it can take a few minutes for public IP to show up"
LogInfo -Message "Wait taill external ip is available from ingress controller"
kubectl get svc -n $demoNamespace -l app=nginx-ingress,component=controller --watch
$ingressController = kubectl get svc -n $demoNamespace -l app=nginx-ingress,component=controller -o json | ConvertFrom-Json
$publicIpAddr = $ingressController.items[0].status.loadBalancer.ingress.ip


LogSte -Step 3 -Message "Install demo app..."
$appTplFile = Join-Path $ingressProvisionFolder "demoApp.tpl"
$appYamlFile = Join-Path $ingressProvisionFolder "demoApp.yaml"
Copy-Item -Path $appTplFile -Destination $appYamlFile -Force 
ReplaceValuesInYamlFile -YamlFile $appYamlFile -PlaceHolder "namespace" $demoNamespace
ReplaceValuesInYamlFile -YamlFile $appYamlFile -PlaceHolder "appName" $appName
ReplaceValuesInYamlFile -YamlFile $appYamlFile -PlaceHolder "tlsSecretName" $tlsSecret
ReplaceValuesInYamlFile -YamlFile $appYamlFile -PlaceHolder "hostName" $hostName
kubectl apply -f $appYamlFile 


LogStep -Step 3 -Message "Installing ingress..."
$ingressTplFile = Join-Path $ingressProvisionFolder "demoIngress.tpl"
$ingressYamlFile = Join-Path $ingressProvisionFolder "demoIngress.yaml"
Copy-Item -Path $ingressTplFile -Destination $ingressYamlFile -Force
ReplaceValuesInYamlFile -YamlFile $ingressYamlFile -PlaceHolder "namespace" $demoNamespace
ReplaceValuesInYamlFile -YamlFile $ingressYamlFile -PlaceHolder "appName" $appName
ReplaceValuesInYamlFile -YamlFile $ingressYamlFile -PlaceHolder "tlsSecretName" $tlsSecret
ReplaceValuesInYamlFile -YamlFile $ingressYamlFile -PlaceHolder "hostName" $hostName
kubectl apply -f $ingressYamlFile 


LogStep -Step 4 -Message "Install cert-manager"
helm install --name cert-manager --namespace $demoNamespace stable/cert-manager


LogStep -Step 5 -Message "Installing cert issuer..."
$issuerTpl = Join-Path $ingressProvisionFolder "issuer.tpl"
$issuerYaml = Join-Path $ingressProvisionFolder "issuer.yaml"
Copy-Item -Path $issuerTpl -Destination $issuerYaml -Force
ReplaceValuesInYamlFile -YamlFile $issuerYaml -PlaceHolder "namespace" $demoNamespace
ReplaceValuesInYamlFile -YamlFile $issuerYaml -PlaceHolder "appName" $appName
ReplaceValuesInYamlFile -YamlFile $issuerYaml -PlaceHolder "tlsSecretName" $tlsSecret
ReplaceValuesInYamlFile -YamlFile $issuerYaml -PlaceHolder "hostName" $hostName
ReplaceValuesInYamlFile -YamlFile $issuerYaml -PlaceHolder "ownerEmail" $ownerEmail
kubectl apply -f $issuerYaml 


LogStep -Step 6 -Message "Installing certificate..."
$certTpl = Join-Path $ingressProvisionFolder "certificate.tpl"
$certYaml = Join-Path $ingressProvisionFolder "certificate.yaml"
Copy-Item -Path $certTpl -Destination $certYaml -Force
ReplaceValuesInYamlFile -YamlFile $certYaml -PlaceHolder "namespace" $demoNamespace
ReplaceValuesInYamlFile -YamlFile $certYaml -PlaceHolder "appName" $appName
ReplaceValuesInYamlFile -YamlFile $certYaml -PlaceHolder "tlsSecretName" $tlsSecret
ReplaceValuesInYamlFile -YamlFile $certYaml -PlaceHolder "hostName" $hostName
ReplaceValuesInYamlFile -YamlFile $certYaml -PlaceHolder "ownerEmail" $ownerEmail
kubectl apply -f $certYaml 



LogStep -Step 7 -Message "Creating DNS zone..."
$dnsZone = az network dns zone create -g $bootstrapValues.global.resourceGroup -n $domainName | ConvertFrom-Json
$dnsRecord = az network dns record-set a add-record -g $bootstrapValues.global.resourceGroup -z $dnsZone.name -n $hostEnvironment -a $publicIpAddr | ConvertFrom-Json



# clear up
helm delete nginx-ingress --purge 