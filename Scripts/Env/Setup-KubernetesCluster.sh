az login
az account list --output table 
az account set --subscription xiaodoli

# create resource group
az group create --name xdK8S --location eastus

# use ACR
az acr create -g xdK8S -n xdContainerRegistry --sku Basic
az acr login -n xdContainerRegistry
az acr list -o table
az acr update -n xdcontainerregistry --admin-enabled true 
az acr repository list -n xdContainerRegistry -o table  

# get ACR username/password
acrUsername="xdcontainerregistry"
acrPassword="$(az acr credential show -n xdcontainerregistry --query ""passwords[0].value"")"

# this took >30 min!! Go grab a coffee.
az aks create \
    --resource-group xdK8S \
    --name xdK8SCluster \
    --generate-ssh-keys \
    --dns-name-prefix xdli \
    --node-count 3 \
    --node-vm-size Standard_DS1

az aks list -o table

# if see error No module named '_cffi_backend'
# run `brew link --overwrite python3`

# retrieves kubeconfig info from cluster and merges into current kubeconfig on local machine
# if you have vs code extension installed, you can browse into node/pod/service/rc (nice!)
az aks get-credentials -n xdK8SCluster -g xdK8S

# creates a proxy tunnel and open dashboard (note: it's using port 8001)
az aks browse -g xdK8S -n xdK8SCluster &

# grant aks read access to acr
aksSvcPrincipalAppId="$(az aks show -g xdK8S -n xdK8SCluster --query ""servicePrincipalProfile.clientId"" -o tsv)" 
acrId="$(az acr show -n xdcontainerregistry -g xdK8S --query ""id"" -o tsv)"
az role assignment create --assignee $aksSvcPrincipalAppId --role Reader --scope $acrId

# set AKS acr secrets
ACR_NAME="xdcontainerregistry"
SERVICE_PRINCIPAL_NAME="xd_acr-service-principal"
EMAIL="xiaodoli@microsoft.com"
ACR_LOGIN_SERVER=$(az acr show -n $ACR_NAME --query loginServer -o tsv)
ACR_REGISTRY_ID=$(az acr show -n $ACR_NAME --query id -o tsv)
az ad sp list 
SP_PASSWD=$(az ad sp create-for-rbac -n $SERVICE_PRINCIPAL_NAME --role Reader --scopes $ACR_REGISTRY_ID --query password -o tsv)
CLIENT_ID=$(az ad sp show --id http://$SERVICE_PRINCIPAL_NAME --query appId -o tsv)
echo "Service principal ID: $CLIENT_ID"
echo "Service principal password: $SP_PASSWD"
k create secret docker-registry acr-auth --docker-server $ACR_LOGIN_SERVER --docker-username $CLIENT_ID --docker-password $SP_PASSWD --docker-email $EMAIL

# create deployment using ACR image
k create -f src/aks-helloworld/aci-helloworld.yaml 
k apply -f src/aks-helloworld/aci-helloworld.yaml 

# set nodes count to desired number (this took ~10 min, super slow!!)
az aks scale -n xdK8SCluster -g xdK8S -c 10 
az aks scale -n xdK8SCluster -g xdK8S -c 2

# shows current control plane and agent pool version, available upgrade versions
# az aks get-versions -n xdK8SCluster -g xdK8S --location eastus

# upgrades
az aks upgrade -n xdK8SCluster -g xdK8S -k 1.9.6

# switch to different cluster
k config use-context minikube
k config use-context xdK8SCluster

# use helm/chart (tiller service deployed to kube-system namespace)
kubectl create -f ./helm-rbac.yaml 
helm init --service-account tiller
helm search
helm repo update
helm install stable/mysql
helm list 
helm delete ugly-billygoat

docker pull microsoft/aci-helloworld
docker images
docker tag microsoft/aci-helloworld xdcontainerregistry.azurecr.io/aci-helloworld:v1 
docker push xdcontainerregistry.azurecr.io/aci-helloworld
az acr repository list -n xdContainerRegistry -o table  
az acr repository show-tags -n xdContainerRegistry --repository aci-helloworld -o table