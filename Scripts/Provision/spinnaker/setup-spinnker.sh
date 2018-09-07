#!/bin/bash 


echo "Installing halyard..."

echo "Enable azure provider..."
hal config provider azure enable

echo "Setup azure provider..."
account = "Spinaker"
az ad sp create-for-rbac --name $account 
hal config provider azure account add my-azure-account \
  --client-id $APP_ID \
  --tenant-id $TENANT_ID \
  --subscription-id $SUBSCRIPTION_ID \
  --default-key-vault $VAULT_NAME \
  --default-resource-group $RESOURCE_GROUP \
  --app-key