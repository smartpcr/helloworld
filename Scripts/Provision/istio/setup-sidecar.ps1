$istioDemoFolder = $PSScriptRoot
if (!$istioDemoFolder) {
    $istioDemoFolder = Get-Location
}

$deploymentTplFile = Join-Path $istioDemoFolder "helloworld-deployment.tpl"
$deploymentYamlFile = Join-Path $istioDemoFolder "helloworld-deployment.yaml"
Copy-Item $deploymentTplFile -Destination $deploymentYamlFile -Force
# istioctl kube-inject -f $deploymentYamlFile | kubectl apply -f -
kubectl label namespace default istio-injection=enabled 
kubectl get namespace -L istio-injection 

# validation steps:
# 1) kubectl api-versions | grep admissionregistration
# admissionregistration.k8s.io/v1alpha1
# admissionregistration.k8s.io/v1beta1
# 2) make sure the following response is not empty
# kubectl get mutatingwebhookconfiguration istio-sidecar-injector -o yaml

kubectl apply -f $deploymentYamlFile