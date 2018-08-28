apiVersion: certmanager.k8s.io/v1alpha1
kind: Issuer
metadata:
  name: {{ .Values.appName }}-letsncrypt-prod
  namespace: {{ .Values.namespace }}
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: {{ .Values.ownerEmail }}
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: {{ .Values.appName }}-letsncrypt-prod
    # Enable HTTP01 validations
    http01: {}
