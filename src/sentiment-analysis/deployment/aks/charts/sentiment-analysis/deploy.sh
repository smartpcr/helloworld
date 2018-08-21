#!/bin/bash

# Stop on error.
set -e
SecretsFile=/mnt/secrets/secrets.yaml
# Read the service principal password from the secret volume.
aksServicePrincipalPassword=$(cat /mnt/secrets/aksServicePrincipalPassword)
deploymentServicePrincipalPassword=$(cat /mnt/secrets/deploymentServicePrincipalPassword)
ingressCaCrt=$(cat /mnt/secrets/ingressCaCrt)
ingressTlsCrt=$(cat /mnt/secrets/ingressTlsCrt)
ingressTlsKey=$(cat /mnt/secrets/ingressTlsKey)
encryptionKey0Value=$(cat /mnt/secrets/encryptionKey0Value)

# Use the service principal to login to the AKS cluster.
az login --service-principal -u "$DeploymentServicePrincipalUserName" -p "$deploymentServicePrincipalPassword" --tenant "$TenantId"
az account set -s "$DeploymentSubscriptionId"
#
# Create file for kv secrets to pass into helm install
# Some secrets may be to long for --set
cat >$SecretsFile <<EOL
aksClusterName: ${ClusterResourceName}
ingressCaCrt: ${ingressCaCrt}
ingressTlsCrt: ${ingressTlsCrt}
ingressTlsKey: ${ingressTlsKey}
imagePassword: ${aksServicePrincipalPassword}
encryptionKey0Value: ${encryptionKey0Value}
databaseAuthorizationKeys:
EOL

# Split documentDB regions from string to array
regionsArray=$(echo $DocumentDBRegionsStr | tr ";" "\n")
# Query CosmosDb keys
for region in $regionsArray
do
    dbResourceName="azcfg-$EnvironmentName-$region"
    dbResourceGroup="$DocumentDBResourceGroupPrefix$(echo $region | tr '[:lower:]' '[:upper:]')"
    dbAuthKey="$(az cosmosdb list-keys -n $dbResourceName -g $dbResourceGroup --query primaryMasterKey -o tsv)"
    echo "  $region: $dbAuthKey" >> $SecretsFile
done

# Connect with Aks
az aks get-credentials -g "$ResourceGroupName" -n "$ClusterResourceName"

# Deploy the helm chart.
helm init --upgrade --wait
helm upgrade "$HelmReleaseName" --install -f "$HelmParametersFileName" -f $SecretsFile CustomServiceName-*.tgz

interval=20
total=60
counter=1
# default timeout 20 * 60 = 1200 sec = 20 min
# release status: https://github.com/helm/helm/blob/7cad59091a9451b2aa4f95aa882ea27e6b195f98/_proto/hapi/release/status.proto#L26
while [ $counter -le $total ]; do
    releaseMessage="$(helm status $HelmReleaseName)"
    # grep doesn't support option -P(perl regex) when run this script in Ev2 machine, has to match the fixed string
    # TODO (yijia): use jq lib to process releaseMessage with output format in JSON 
    if [[ $releaseMessage = *"STATUS: DEPLOYED"* ]]; then
        echo "Deployment has been succeed."
        set 0
        break
    elif [[ $releaseMessage = *"STATUS: PENDING"* ]]; then
        sleep ${interval}
    else
        echo "Deployment has been failed. Release: $HelmReleaseName. AksClusterName: $ClusterResourceName. RG: $ResourceGroupName"
        set 2
        break
    fi
    ((counter++))
done

if [[ $counter -eq $total ]]; then
    echo "Timeout to run health check."
    set 3
fi