kubectl create -f rbac.yml
kubectl create -f prometheus.yml
kubectl create -f prometheus-resource.yml 
kubectl create -f kubernetes-monitoring.yml 
kubectl create -f example-app.yml 

# run the following to cleanup
kubectl delete service,deployment example-app node-exporter kube-state-metrics prometheus-operator prometheus prometheus-operated
kubectl delete statefulset.apps/prometheus-prometheus
kubectl delete daemonset.apps/node-exporter


kubectl apply --filename https://raw.githubusercontent.com/giantswarm/kubernetes-prometheus/master/manifests-all.yaml
kubectl delete namespace monitoring 