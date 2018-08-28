apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  labels:
    app: {{ .Values.label }}
    aadpodidbinding: {{ .Values.label }}
  name: {{ .Values.label }}
  namespace: default
spec:
  template:
    metadata:
      labels:
        app: {{ .Values.label }}
        aadpodidbinding: {{ .Values.label }}
    spec:
      containers:
      - name: {{ .Values.label }}
        image: "mcr.microsoft.com/k8s/aad-pod-identity/demo:1.2"
        imagePullPolicy: Always
        args:
          - "--subscriptionid={{ .Values.subscriptionId }}"
          - "--clientid={{ .Values.clientId }}"
          - "--resourcegroup={{ .Values.nodeResourceGroup }}"
          - "--aad-resourcename=https://vault.azure.net"
          # TO SPECIFY NAME OF RESOURCE TO GRANT TOKEN ADD --aad-resourcename
          # this demo defaults aad-resourcename to https://management.azure.com/
          # e.g. - "--aad-resourcename=https://vault.azure.net"
        env:
        - name: MY_POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: MY_POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: MY_POD_IP
          valueFrom:
            fieldRef:
              fieldPath: status.podIP