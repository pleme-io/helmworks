{{/*
pleme-lareira.ingress — LAN-side Ingress with cert-manager TLS.

Emits a networking.k8s.io/v1 Ingress when .Values.ingress.enabled is true.
TLS is provisioned via cert-manager when .Values.ingress.tls.enabled is
true; secret name auto-derives from {fullname}-tls when not specified.

Authentik forward-auth annotations are auto-merged when
.Values.authentik.enabled is true (see _authentik.tpl).

Use in consumer chart templates/ingress.yaml:

  {{- if include "pleme-lareira.enabled" . }}
  {{- include "pleme-lareira.ingress" . }}
  {{- end }}
*/}}

{{- define "pleme-lareira.ingress" -}}
{{- if .Values.ingress.enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
{{- $svcPort := default (index .Values.service.ports 0).port .Values.ingress.servicePort }}
{{- $tlsSecret := default (printf "%s-tls" $fullname) .Values.ingress.tls.secretName }}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ $fullname }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- if .Values.ingress.tls.enabled }}
    cert-manager.io/cluster-issuer: {{ .Values.ingress.tls.issuer | quote }}
    {{- end }}
    {{- include "pleme-lareira.authentik.annotations" . | nindent 4 }}
    {{- with .Values.ingress.annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  ingressClassName: {{ .Values.ingress.className | quote }}
  {{- if .Values.ingress.tls.enabled }}
  tls:
    - hosts:
        {{- range .Values.ingress.hosts }}
        - {{ .host | quote }}
        {{- end }}
      secretName: {{ $tlsSecret | quote }}
  {{- end }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range (default (list (dict "path" "/" "pathType" "Prefix")) .paths) }}
          - path: {{ .path | quote }}
            pathType: {{ .pathType | default "Prefix" | quote }}
            backend:
              service:
                name: {{ $fullname }}
                port:
                  number: {{ $svcPort }}
          {{- end }}
    {{- end }}
{{- end }}
{{- end -}}
