apiVersion: v1
kind: Pod
metadata:
  name: keyvault-demo
spec:
  containers:
  - name: keyvault-demo
    image: nginx
    volumeMounts:
    - name: test
      mountPath: /kvmnt
      readOnly: true
  volumes:
  - name: test
    flexVolume:
      driver: "azure/kv"
      secretRef:
        name: {{ .Values.kvSecrets }}
      options:
        usepodidentity: "false"
        resourcegroup: "{{ .Values.rgName }}"
        keyvaultname: "{{ .Values.vaultName }}"
        keyvaultobjectname: "{{ .Values.secretName }}"
        keyvaultobjectversion: "{{ .Values.version }}"
        keyvaultobjecttype: secret 
        subscriptionid: "{{ .Values.subscriptionId }}"
        tenantid: "{{ .Values.tenantId }}"