#!bin/bash

echo "Downloading istio release..."
curl -L https://git.io/getIstio | sh -
helm template install/kubernetes/helm/istio --name istio --namespace istio-system > $HOME/istio.yaml
kubectl create namespace istio-system
echo "Installing istio..."
kubectl apply -f $HOME/istio.yaml

echo "delete istio from cluster"
helm delete --purge istio

echo "installing prometheus..."
helm repo add coreos https://s3-eu-west-1.amazonaws.com/coreos-charts/stable/
helm install coreos/prometheus-operator --name prometheus-operator --namespace monitoring
helm install coreos/kube-prometheus --name kube-prometheus --set global.rbacEnable=true --namespace monitoring