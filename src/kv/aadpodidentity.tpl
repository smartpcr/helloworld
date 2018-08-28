apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentity
metadata:
  name: {{ .Values.azureIdentityName }}
spec:
  type: {{ .Values.aadPodIdentityType }}
  ResourceID: {{ .Values.azureIdentityId }}
  ClientID: {{ .Values.servicePrincipalClientId }}