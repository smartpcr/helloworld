# Download istio binary 
$istioBinaryFolder = "E:\work\github\container\mesh\istio-1.1.0\istio-1.1.0.snapshot.0"
Set-Location $istioBinaryFolder
$helmFolder = Join-Path $istioBinaryFolder "install/kubernetes/helm/istio"


Write-Host "Installing istio with release name 'istio' and namespace 'istio-system'..."
kubectl apply -f "$istioBinaryFolder/install/kubernetes/helm/helm-service-account.yaml"
helm install $helmFolder --name istio --namespace istio-system

