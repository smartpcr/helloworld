apiVersion: certmanager.k8s.io/v1alpha1
kind: Certificate
metadata:
  name: {{ .Values.appName }}
  namespace: {{ .Values.namespace }}
spec:
  secretName: {{ .Values.tlsSecretName }}
  issuerRef:
    name: {{ .Values.appName }}-letsncrypt-prod
  commonName: {{ .Values.hostName }}
  dnsNames:
  - {{ .Values.hostName }}
  acme:
    config:
    - http01:
        ingress: {{ .Values.appName }}
      domains:
      - {{ .Values.hostName }}
