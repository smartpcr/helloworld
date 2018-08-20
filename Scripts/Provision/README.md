# Bootstrap

***Terraform azure provider does NOT support service principal authentication via certificate.*** 

All terraform provisioning step requires service principal has already been created and secrets are already stored in key vault. 

The service principal will have contributor to the subscription and KV CRUD permission policy.

``` powershell
./Scripts/Env/Setup-ServicePrincipal.ps1
./Scripts/Provision/Setup-TerraformAccess.ps1
```

# Provision 

## remote state

terraform state is divided into dev, test, and prod environment. States are stored in the following azure resources:
lock table: cosmosdb
tfstates: blob storage

Ideally, each environment should be provisioned using different service principal and their scopes limited to different subscription/group. But for PoC, we will only use one service principal to provision all environments

## KV secret data source

terraform uses external data source to retrieve KV secrets (powershell). This is shown in ___/Provision/Auth___

## VM devbox

## ACR 

## AKS

3. Resources to be provisioned

- ACR, service principal should have RW rights to it
- AKS cluster
    - terraform uses the same service principal to create cluster
    - AKS also have its own service principal (with password) authentication and connect to cluster
    - each namespace should have its own service principal for RBAC-based isolation and roleBinding
    - 