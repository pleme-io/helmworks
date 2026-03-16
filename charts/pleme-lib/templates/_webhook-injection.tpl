{{/*
pleme-lib.webhookInjection — Mutating Admission Webhook template.
Generic pattern for K8s sidecar injection webhooks.

Usage:
  {{- include "pleme-lib.webhookInjection" . }}

Requires values:
  webhook:
    enabled: true
    port: 8443
    failurePolicy: Ignore  # or Fail
    sidecarImage: { repository, tag }
    metricsPort: 8090
    replicas: 2
*/}}
{{- define "pleme-lib.webhookInjection" -}}
{{- if (.Values.webhook).enabled }}
---
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: {{ include "pleme-lib.fullname" . }}-webhook
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
webhooks:
  - name: {{ include "pleme-lib.fullname" . }}.mutate
    clientConfig:
      service:
        name: {{ include "pleme-lib.fullname" . }}-webhook
        namespace: {{ include "pleme-lib.namespace" . }}
        path: /mutate
        port: {{ .Values.webhook.port | default 443 }}
      caBundle: ""
    rules:
      - operations: ["CREATE", "UPDATE"]
        apiGroups: [""]
        apiVersions: ["v1"]
        resources: ["pods"]
    failurePolicy: {{ .Values.webhook.failurePolicy | default "Ignore" }}
    sideEffects: None
    admissionReviewVersions: ["v1", "v1beta1"]
    namespaceSelector:
      matchExpressions:
        - key: {{ include "pleme-lib.fullname" . }}-injection
          operator: In
          values: ["enabled"]
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "pleme-lib.fullname" . }}-webhook
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  ports:
    - port: {{ .Values.webhook.port | default 443 }}
      targetPort: {{ .Values.webhook.port | default 8443 }}
      protocol: TCP
      name: webhook
    {{- if (.Values.webhook).metricsPort }}
    - port: {{ .Values.webhook.metricsPort }}
      targetPort: {{ .Values.webhook.metricsPort }}
      protocol: TCP
      name: metrics
    {{- end }}
  selector:
    {{- include "pleme-lib.selectorLabels" . | nindent 4 }}
    app.kubernetes.io/component: webhook
{{- end }}
{{- end }}
