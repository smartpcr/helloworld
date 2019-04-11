# Goal

This is a hello world example to achieve the following goals:
- automatically provision 3 clusters using AKS: 
    - dev (individual)
    - team (test) 
    - prod (multiple regions) with BCP support
- CI/CD pipeline: from code check in, build (unit tests), deploy to cluster and run integration test, push to team cluster
- multi-tenant support, authenticate individual user and orgnization using AAD B2C, configurable isolation at the following levels:
    - cluster (different region/country)
    - service namespace
    - shared pod/container
    - storage: different account/db/collection/partition
- RBAC 
- Monitoring, audit, alert
    - tracing
        - MDS/MDM/IFx (within Microsoft)
        - Application Insights
        - Prometheus, fluntd
    - Storage: elastic search, kusto, azure blob, azure table
    - Health metric for node and service
    - alert: email, text, phone
- The system should be flexible to support multiple technologies (nodejs, java and c#)
    - There is one-to-one mapping between feature and microservice 
    - each microservice is a unit of deployment (pod)
    - a microservice is implemented using same language 
    - each team owns 1 or more microservices, cluster authn/authz is controled at team level (excluding prod cluster)
- Rolling update, support mixed versions
    - Flighting and A/B testing
- Auto scale
    - worker node count within cluster
    - pod/service count within cluster

# Azure Resource Provisioning

1. Terraform is used to provision/setup baseline
2. Helm is used to deploy to AKS
3. Service principal (AAD)

# Product to build

The product will be used by other software developers to:
- turn on/off feature of a particular microservice
- route users to particular combination of features
- service dependency is managed by tags, i.e. Service A (v1.0) can only talk to Service B (v1.4)
- realtime dashboard of deployments, health and traffic

# Instruction 

## Bootstrap Environment

1. Create a new environment. for example, for `dev` envorinment, set its override values here: `\Scripts\Env\dev\values.yaml`
2. Setup service principal authentication and devbox pre-requirements by running `.\Scripts\bootstrap.ps1 -EnvName dev`
3. Navigate to azure portal and AAD app registration, look for cluster app, make sure:
    - its secret is set: 
        ![aad app secret](https://github.com/smartpcr/helloworld/blob/master/Instruction/cluster-app-secrets.png)
    - API permissions are granted
        ![aks app permission](https://github.com/smartpcr/helloworld/blob/master/Instruction/cluster-app-permissions.png)
    - owner is set
        ![aks app owner](https://github.com/smartpcr/helloworld/blob/master/Instruction/cluster-app-owner.png)
4. Look for aks client app, make sure:
    - owner is set 
        ![client app owner](https://github.com/smartpcr/helloworld/blob/master/Instruction/client-app-owner.png)
    - its permission is set 
        ![client app permission](https://github.com/smartpcr/helloworld/blob/master/Instruction/client-app-permissions.png)
    - API permission is granted, make sure user impersonation is checked
        ![client app impersonation](https://github.com/smartpcr/helloworld/blob/master/Instruction/client-app-impersonation.PNG)
    
