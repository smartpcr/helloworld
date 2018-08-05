location="westus2"
loc="wus2"
subscriptionName=BizSpark-xdxli
productName=helloworld
productShortName=hw
envName=dev
owner=xiaodoli
currentUserPrincipalName=lingxd_gmail.com#EXT#@xdxlioutlook.onmicrosoft.com

# login and set subscription
az login
az account set -s $subscriptionName

# create resource group 
rgName=${productName}-${envName}-${owner}-${loc}-rg
az group create -n $rgName -l $location

# create key vault 
kvName=${productShortName}-${envName}-${owner}-kv # make sure vault name length <= 24
kvNameSize=${#kvName}
if [ $kvNameSize \> 24 ]; then 
    echo "Error: pick different valut name"
    exit 1
else 
    echo "Vault name is $kvName"
fi
az keyvault create -g $rgName -n $kvName -l $location

# create and add certificate to key vault 
certName=${productName}-${envName}-${owner}-${loc}-sp
az keyvault certificate create -n $certName --vault-name $kvName \
    -p "$(az keyvault certificate get-default-policy)"

# create service principal and use certificate to authenticate
subscriptionId=$(az account show --query id -o tsv)
userName=$(az account show --query user.name)
spName=${productName}-${envName}-${owner}-${loc}-sp

az ad sp create-for-rbac -n $spName --role contributor \
    --keyvault $kvName --cert $certName 

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