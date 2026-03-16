{{/*
pleme-lib.csiProvider — CSI Secrets Store provider DaemonSet template.
Generic pattern for K8s CSI Driver secret providers.

Usage:
  {{- include "pleme-lib.csiProvider" . }}

Requires values:
  csiProvider:
    enabled: true
    image: { repository, tag, pullPolicy }
    socketPath: /tmp/provider.sock
    kubeletPath: /var/lib/kubelet
    providerDir: /etc/kubernetes/secrets-store-csi-providers
    healthPort: 8080
    resources: { requests, limits }
*/}}
{{- define "pleme-lib.csiProvider" -}}
{{- if (.Values.csiProvider).enabled }}
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: {{ include "pleme-lib.fullname" . }}-csi-provider
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
      app.kubernetes.io/component: csi-provider
  template:
    metadata:
      labels:
        {{- include "pleme-lib.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: csi-provider
    spec:
      serviceAccountName: {{ include "pleme-lib.serviceAccountName" . }}
      containers:
        - name: provider
          image: {{ include "pleme-lib.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "Always" }}
          args:
            - "--socket-path={{ .Values.csiProvider.socketPath | default "/tmp/provider.sock" }}"
            - "--health-port={{ .Values.csiProvider.healthPort | default "8080" }}"
          ports:
            - containerPort: {{ .Values.csiProvider.healthPort | default 8080 }}
              name: health
          livenessProbe:
            httpGet:
              path: /health/ready
              port: health
            initialDelaySeconds: 5
            periodSeconds: 10
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          securityContext:
            {{- include "pleme-lib.containerSecurityContext" . | nindent 12 }}
          volumeMounts:
            - name: provider-dir
              mountPath: {{ .Values.csiProvider.providerDir | default "/etc/kubernetes/secrets-store-csi-providers" }}
            - name: kubelet-pods
              mountPath: {{ .Values.csiProvider.kubeletPath | default "/var/lib/kubelet" }}/pods
              mountPropagation: HostToContainer
      volumes:
        - name: provider-dir
          hostPath:
            path: {{ .Values.csiProvider.providerDir | default "/etc/kubernetes/secrets-store-csi-providers" }}
        - name: kubelet-pods
          hostPath:
            path: {{ .Values.csiProvider.kubeletPath | default "/var/lib/kubelet" }}/pods
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
{{- end }}
