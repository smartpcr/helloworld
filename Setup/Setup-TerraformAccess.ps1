az login
az account set --subscription "RRD MSDN ULtimate"
$subscriptionId = $(az account show --query "id" -o tsv)
$createSpOutput = $(az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/$subscriptionId" --name "terraform-aks-test")
$createdSpn = $createSpOutput | ConvertFrom-Json

[System.Environment]::SetEnvironmentVariable("terraform_azure_app_id", $createdSpn.appId, [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable("terraform_azure_app_password", $createdSpn.password, [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable("terraform_azure_tenant_id", $createdSpn.tenant, [System.EnvironmentVariableTarget]::User)
[System.Environment]::SetEnvironmentVariable("terraform_azure_subscription_id", $subscriptionId, [System.EnvironmentVariableTarget]::User)
