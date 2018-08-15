$location="westus2"
$loc="wus2"
$subscriptionName="RRD MSDN Ultimate"
$productName="helloworld"
$productShortName="hw"
$envName="dev3"
$owner="xiaodoli"
# $currentUserPrincipalName=lingxd_gmail.com#EXT#@xdxlioutlook.onmicrosoft.com

# login and set subscription
az login
az account set -s $subscriptionName

# create resource group 
$rgName="${productName}-${envName}-${owner}-${loc}-rg"
az group create -n $rgName -l $location

# create key vault 
$kvName="${productShortName}-${envName}-${owner}-kv" # make sure vault name length <= 24
az keyvault create -g $rgName -n $kvName -l $location

# create and add certificate to key vault 
$certName="${productName}-${envName}-${owner}-${loc}-sp-cert2"
$defaultPolicyFile = "C:\users\xd\desktop\default_policy.json"
$pfxCertFile = "C:\users\xd\desktop\$certName.pfx"
$pemCertFile = "C:\users\xd\desktop\$certName.pem"
$keyCertFile = "C:\users\xd\desktop\$certName.key"

# New-AzureKeyVaultCertificatePolicy -SubjectName $SubjectName -IssuerName Self -ValidityInMonths 12

az keyvault certificate get-default-policy -o json | Out-File $defaultPolicyFile -Encoding utf8 
az keyvault certificate create -n $certName --vault-name $kvName -p @$defaultPolicyFile

az keyvault secret download --vault-name $kvName -n $certName -e base64 -f $pfxCertFile
openssl pkcs12 -in $pfxCertFile -clcerts -nodes -out $keyCertFile 
openssl rsa -in $keyCertFile -out $pemCertFile

# verify 
openssl rsa -in $keyCertFile -check
openssl x509 -in $keyCertFile -text -noout

# create service principal and use certificate to authenticate
$subscriptionId = az account show --query id -o tsv
$tenenatId = az account show --query tenantId -o tsv 

$spName="${productName}-${envName}-${owner}-${loc}-sp2"

az ad sp create-for-rbac -n $spName --role contributor --keyvault $kvName --cert $certName 

az login --service-principal -u "http://$spName" -p $keyCertFile --tenant $tenenatId --debug

az ad sp show --id http://${spName}
aadAppId=$(az ad sp show --id http://${spName} --query appId -o tsv)
aadObjId=$(az ad sp show --id http://${spName} --query objectId -o tsv)

# grant key vault access to service principal
az keyvault set-policy -g $rgName -n $kvName --object-id $aadObjId --certificate-permissions list get create delete update
az keyvault set-policy -g $rgName -n $kvName --object-id $aadObjId --key-permissions list get create delete update
az keyvault set-policy -g $rgName -n $kvName --object-id $aadObjId --secret-permissions list get create delete update

# grant service principal contributor access to current azure resource group 
az role assignment create --assignee $aadObjId --role Contributor --scopes /

# grant current user owner access to service principal
currentUser=$(az ad user list --query "[?contains(userPrincipalName, '${currentUserPrincipalName}')]")


# install certificate to local machine

[System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("dummy"))