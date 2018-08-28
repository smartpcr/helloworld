apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: {{ .Values.appName }}
  namespace: {{ .Values.namespace }}
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: {{ .Values.appName }} 
    spec:
      containers:
      - name: k8s-demo
        image: wardviaene/k8s-demo
        ports:
        - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.appName }}
  namespace: {{ .Values.namespace }}
spec:
  ports:
  - port: 3000
    targetPort: 3000
    protocol: TCP
  selector:
    app: {{ .Values.appName }}
