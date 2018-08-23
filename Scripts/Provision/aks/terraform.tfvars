resource_group_name = "helloworld-dev4-xiaodoli-wus2-rg"

location = "westus2"

tags = {
  Responsible = "Xiaodong Li"
  Environment = "Dev"
}

# aks
aks_resource_group_name = "k8s-helloworld-dev4-xiaodoli-rg"

aks_name = "k8s-helloworld-dev4-xiaodoli-cluster"

aks_agent_vm_count = "2"

aks_agent_vm_size = "Standard_D2_v2"

k8s_version = "1.11.1"

aks_service_principal_app_id = "41ade730-36f4-4e12-a1f6-d05ecc8ec74c"

dns_prefix = "hw-aks-xd"

aks_ssh_public_key = "/Users/xiaodongli/work/github/containers/helloworld/Scripts/Env/credential/dev/k8s-ssh-helloworld-dev4-xiaodoli-key.pub"

acr_name = "acrxiaodolidev4"

acr_resource_group_name = "acr-xiaodoli-rg"
