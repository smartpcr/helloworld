$SubscriptionName = "RRD MSDN Ultimate"
$VaultName = "hw-dev2-xiaodoli-kv"

az login
az account set --subscription $SubscriptionName
$subscriptionId = $(az account show --query "id" -o tsv)
$createSpOutput = $(az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/$subscriptionId" --name "terraform-aks-test")
$createdSpn = $createSpOutput | ConvertFrom-Json

[System.Environment]::SetEnvironmentVariable("terraform_azure_app_id", $createdSpn.appId, [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable("terraform_azure_app_password", $createdSpn.password, [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable("terraform_azure_tenant_id", $createdSpn.tenant, [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable("terraform_azure_subscription_id", $subscriptionId, [System.EnvironmentVariableTarget]::User)


az keyvault secret set --vault-name $VaultName --name "terraform-azure-app-id" --value $env:terraform_azure_app_id
az keyvault secret set --vault-name $VaultName --name "terraform-azure-app-password" --value $env:terraform_azure_app_password
az keyvault secret set --vault-name $VaultName --name "terraform-azure-tenant-id" --value $env:terraform_azure_tenant_id
az keyvault secret set --vault-name $VaultName --name "terraform-azure-subscription-id" --value $env:terraform_azure_subscription_id