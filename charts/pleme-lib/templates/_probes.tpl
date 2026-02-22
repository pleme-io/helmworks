{{/*
pleme-lib: probe templates

Standard probe patterns for pleme-io services.
All services expose /healthz (liveness) and /readyz (readiness).
*/}}

{{/*
Liveness probe
*/}}
{{- define "pleme-lib.livenessProbe" -}}
httpGet:
  path: {{ .Values.health.path | default "/healthz" }}
  port: {{ .Values.health.port | default "http" }}
initialDelaySeconds: {{ .Values.health.livenessInitialDelay | default 5 }}
periodSeconds: {{ .Values.health.livenessPeriod | default 10 }}
failureThreshold: {{ .Values.health.livenessFailureThreshold | default 3 }}
{{- end }}

{{/*
Readiness probe
*/}}
{{- define "pleme-lib.readinessProbe" -}}
httpGet:
  path: {{ .Values.health.readyPath | default "/readyz" }}
  port: {{ .Values.health.port | default "http" }}
initialDelaySeconds: {{ .Values.health.readinessInitialDelay | default 5 }}
periodSeconds: {{ .Values.health.readinessPeriod | default 5 }}
failureThreshold: {{ .Values.health.readinessFailureThreshold | default 2 }}
{{- end }}

{{/*
Startup probe (disabled by default)
*/}}
{{- define "pleme-lib.startupProbe" -}}
{{- if .Values.startupProbe.enabled }}
httpGet:
  path: {{ .Values.startupProbe.path | default "/healthz" }}
  port: {{ .Values.startupProbe.port | default "http" }}
initialDelaySeconds: {{ .Values.startupProbe.initialDelaySeconds | default 0 }}
periodSeconds: {{ .Values.startupProbe.periodSeconds | default 5 }}
failureThreshold: {{ .Values.startupProbe.failureThreshold | default 30 }}
{{- end }}
{{- end }}
