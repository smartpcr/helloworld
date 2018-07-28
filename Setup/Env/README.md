# Bootstrap Development Environment

CI/CD pipeline will use a service principal that have access to azure Key Vault and azure resource group. Developers must be granted access to AAD app before running local devbox.

Service principal is granted access to Key Vault via certificate (not password).

## Instruction

__for demo purpose, I will use personal azure subscription so that I can assign roles to AAD app__

1. create key vault with name helloworld_dev_xiaodoli_kv
2. create a self-signed certificate (cn=helloworld_dev_xiaodoli_sp) and add it to key vault
3. create AAD app with id helloworld_dev_xiaodoli_sp and use cert for credential
4. grant current user access to AAD app (only needed for local devbox setup, CI/CD pipeline will use the same service principal)

## Create Self-Signed Certificate

__this is only for dev/test, production certificate will be created from trusted CA and then imported to Key Vault__

1. Create resource group and key vault 
``` bash
location="west us 2"
loc="wus2"
subscriptionName=xdxli
productName=helloworld
envName=dev
rand=xiaodoli

az login
az account set -s $subscriptionName
rgName="$productName_$envName_$rand_$loc_rg"
az group create -l $location -n $rgName -y
kvName="$productName_$envName_$rand_kv"
az keyvault create -g $rgName -n $kvName -l $location
```

2. Create certificate
``` bash
certName=$spName
az keyvault certificate create -n $certName --vault-name $kvName \
-p "$(az keyvault certificate get-default-policy)"

```

3. Create service principal for RBAC
``` bash
subscriptionId=$(az account show).id
userObjectId=
spName="$productName_$envName_$rand_$loc_sp"
az ad sp create-for-rbac -n $spName --role contributor \
--keyvault $kvName --cert $certName \
--scopes /subscription/$subscriptionId/resourceGroups/$rgName
```

4. Grant current user to AAD role
``` bash
az role assignment create --assignee $aadAppId --role Contributor