kubectl create -f rbac.yml
kubectl create -f prometheus.yml
kubectl create -f prometheus-resource.yml 
kubectl create -f kubernetes-monitoring.yml 
kubectl create -f example-app.yml 

kubectl apply --filename https://raw.githubusercontent.com/giantswarm/kubernetes-prometheus/master/manifests-all.yaml