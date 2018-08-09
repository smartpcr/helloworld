###########################################################
# This script setup devbox on mac
# 1) install git credential manager
# 2) install .net core sdk 2.1
# 3) install azure cli 
# 4) install docker and enable hyper-v feature
# 5) install kubectl (kubernetes cli)
# 6) install helm and draft
# 7) minikube on windows is not working (via kubeadmin)
###########################################################


# brew update
brew update 

# manually install the following
# 1. jdk (do not use v9 or higher if you use git credential manager)
# 2. docker
# 3. python3
# 4. nodejs
# 5. dotnet sdk

echo "install git credential manager"
# java 9 or higher won't work, if credential manager was already installed with new version of java, it need to be 
# uninstalled first!!
brew cask install caskroom/versions/java8
brew install git-credential-manager
git-credential-manager install

echo "installing azure cli"
brew install azure-cli
az -v  

echo "installing kubernetes-cli"
brew install kubectl

echo "installing virtualbox"
brew cask install virtualbox

echo "installing minikube"
brew cask install minikube 

echo "verifying..."
docker --version 
docker-compose --version 
docker-machine --version 
vboxManage --version
minikube version 
kubectl version --client 

echo "starting minikue..."
minikube start 
kubectl cluster-info 
kubectl get nodes 
kubectl get pods
kubectl get deployments
kubectl get services

echo "running http through deployment/pod"
kubectl run http --image=httpd
kubectl get pods 
kubectl port-forward http-78bcd64d6c-t2m7r 8002:80 &
kubectl describe pods http-78bcd64d6c-t2m7r
curl http://localhost:8002
kubectl get deployments
kubectl delete deployments http

echo "running http through service"
kubectl run http --image=httpd
kubectl expose deployment http --port=80 --type=NodePort
kubectl get service http -o yaml
curl http://192.168.99.100:32586 
kubectl delete services http 

echo "working with DNS"
minikube ssh 
# run the following in minikube
docker ps -a | grep "dns"
exit
kubectl get pods
kubectl exec busybox cat /etc/resolv.conf
# ingress
minikube addons enable ingress
kubectl create -f ./src/configs/ingress.yaml

echo "installing helm"
brew install kubernetes-helm

echo "installing draft"
brew tap azure/draft && brew install draft
draft init 
eval $(minikube docker-env)

kubectl create -f ./helm-rbac.yaml 
helm init --service-account tiller
helm search
helm repo update

echo "installing wordpress..."
helm install stable/wordpress

echo "installing terraform..."
brew install terraform