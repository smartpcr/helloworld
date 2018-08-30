#!bin/bash

echo "Start with a clean slate"
kubectl delete all --all -n istio-system 

echo "Use istio 1.0.1 binary"
cd ~/
curl -o istio-1.0.1.tar.gz -L https://github.com/istio/istio/releases/download/1.0.1/istio-1.0.1-osx.tar.gz
tar -xzvf istio-1.0.1.tar.gz 
ln -sf ~/istio-1.0.1 ~/istio 
rm istio-1.0.1.tar.gz 
cp ~/istio/bin/istioctl /Usr/local/bin/  

cd ~/istio
echo "Installing istio (using demo, that include a few add ons)..."
kubectl apply -f ~/istio/install/kubernetes/istio-demo.yaml --as=admin --as-group=system:masters 
kubectl get pods -n istio-system -w
kubectl get services -n istio-system -w 
