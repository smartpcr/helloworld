apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: nginx
  name: {{ .Values.appName }}
  namespace: {{ .Values.namespace }}
spec:
  tls:
  - secretName: {{ .Values.tlsSecretName }}
    hosts:
    - {{ .Values.hostName }}
  rules:
    - host: {{ .Values.hostName }}
      http:
        paths:
          - backend:
              serviceName: {{ .Values.appName }}
              servicePort: 3000
            path: /

