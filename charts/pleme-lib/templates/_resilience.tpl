{{/*
pleme-lib.resilience — Network slice (CIA).

Renders Istio DestinationRule with circuit breaker, connection pooling,
and outlier detection. Any service gets resilience without hand-writing
Istio resources.

Usage in a chart's templates/resilience.yaml:
  {{- include "pleme-lib.resilience" . }}

Values:
  resilience:
    enabled: true
    circuitBreaker:
      consecutive5xx: 5
      interval: 30s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
    connectionPool:
      maxConnections: 100
      http2MaxRequests: 100
      maxRequestsPerConnection: 10
    retry:
      attempts: 3
      perTryTimeout: 10s
      retryOn: "5xx,reset,connect-failure"
*/}}

{{- define "pleme-lib.resilience" -}}
{{- if .Values.resilience }}
{{- if .Values.resilience.enabled }}
{{- $fullname := include "pleme-lib.fullname" . }}
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: {{ $fullname }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  host: {{ $fullname }}.{{ .Release.Namespace }}.svc.cluster.local
  trafficPolicy:
    {{- if .Values.resilience.connectionPool }}
    connectionPool:
      tcp:
        maxConnections: {{ default 100 .Values.resilience.connectionPool.maxConnections }}
      http:
        h2UpgradePolicy: DEFAULT
        http2MaxRequests: {{ default 100 .Values.resilience.connectionPool.http2MaxRequests }}
        maxRequestsPerConnection: {{ default 10 .Values.resilience.connectionPool.maxRequestsPerConnection }}
    {{- end }}
    {{- if .Values.resilience.circuitBreaker }}
    outlierDetection:
      consecutive5xxErrors: {{ default 5 .Values.resilience.circuitBreaker.consecutive5xx }}
      interval: {{ default "30s" .Values.resilience.circuitBreaker.interval }}
      baseEjectionTime: {{ default "30s" .Values.resilience.circuitBreaker.baseEjectionTime }}
      maxEjectionPercent: {{ default 50 .Values.resilience.circuitBreaker.maxEjectionPercent }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}
