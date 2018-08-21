resource_group_name = "helloworld-dev4-xiaodoli-wus2-rg" 
location = "westus2"
tags = {     
    Responsible = "Xiaodong Li"     
    Environment = "Dev" 
} 
# aks
aks_resource_group_name = "helloworld-dev4-xiaodoli-k8s" 
aks_name = "helloworld-dev4-xiaodoli-k8s" 
aks_agent_vm_count = "2" 
aks_agent_vm_size = "Standard_D2_v2" 
k8s_version = "1.11.1"
aks_service_principal_app_id = "301f388c-e1a9-4bdd-8605-8e959c83752c"
dns_prefix = "hw-aks-xd"
aks_ssh_public_key = "/Users/xiaodongli/work/github/container/helloworld/Scripts/Env/credential/dev/helloworld-dev4-xiaodoli-k8s-cert.pub"
acr_name = "xiaodoliacrdev4"
acr_resource_group_name = "xiaodoli"

