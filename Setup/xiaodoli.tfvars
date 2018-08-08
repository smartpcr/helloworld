
ssh_public_key="~/.ssh/hw-001-dev-wus2-sp.pub"
resource_group_name="hw-001-dev-wus2-rg"
aks_resource_group_name="hw-001-dev-wus2-rg-aks"
tags = {
    Responsible = "Xiaodong Li"
    Environment = "Dev"
}
aks_name="hw-001-dev-wus2-aks"
acr_name="hw001devwus2acr"
acr_sku="Basic"
aks_agent_vm_count = "2"
aks_agent_vm_size = "Standard_D2_v2"
k8s_version = "1.9.6"