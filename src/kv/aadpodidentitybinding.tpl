apiVersion: "aadpodidentity.k8s.io/v1"
kind: AzureIdentityBinding
metadata:
  name: demo1-azure-identity-binding
spec:
  AzureIdentity: {{ .Values.azureIdentityName }}
  Selector: {{ .Values.selectorLabel }}