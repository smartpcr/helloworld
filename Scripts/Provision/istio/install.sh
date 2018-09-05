#!bin/bash

echo "Start with a clean slate"
kubectl delete all --all -n istio-system 
# kubectl delete rolebinding,clusterrolebinding,clusterrole,role,sa,crd --all -n istio-system

echo "Use istio 1.0.1 binary"
cd ~/
curl -o istio-1.0.1.tar.gz -L https://github.com/istio/istio/releases/download/1.0.1/istio-1.0.1-osx.tar.gz
tar -xzvf istio-1.0.1.tar.gz 
ln -sf ~/istio-1.0.1 ~/istio 
rm istio-1.0.1.tar.gz 
cp ~/istio/bin/istioctl /Usr/local/bin/  

cd ~/istio
echo "Installing istio (using demo, that include a few add ons)..."
kubectl apply -f install/kubernetes/helm/istio/templates/crds.yaml
helm template install/kubernetes/helm/istio --name istio --namespace istio-system > $HOME/istio.yaml
kubectl create namespace istio-system
kubectl apply -f $HOME/istio.yaml
kubectl get pods -n istio-system 
kubectl get services -n istio-system 

echo "Manual sidecar injection..."
istioctl kube-inject -f samples/sleep/sleep.yaml | kubectl apply -f -
# kubectl -n istio-system get configmap istio-sidecar-injector -o=jsonpath='{.data.config}' > inject-config.yaml
# kubectl -n istio-system get configmap istio -o=jsonpath='{.data.mesh}' > mesh-config.yaml
# istioctl kube-inject \
#     --injectConfigFile inject-config.yaml \
#     --meshConfigFile mesh-config.yaml \
#     --filename samples/sleep/sleep.yaml \
#     --output sleep-injected.yaml
# kubectl apply -f sleep-injected.yaml

# check feature is available 
kubectl api-versions | grep admissionregistration
# clean up
kubectl delete deployment,service,pod sleep -n default


echo "Setup auto sidecar injection..."

kubectl label namespace default istio-injection=enabled
kubectl get namespace -L istio-injection

kubectl apply -f samples/sleep/sleep.yaml
kubectl get deployment -o wide


