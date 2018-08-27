apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: {{ .Values.azureIdentityName }}
spec:
  type: 1
  ResourceID: {{ .Values.azureIdentityId }}
  ClientID: {{ .Values.servicePrincipalClientId }}