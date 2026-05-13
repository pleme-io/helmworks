{{/*
pleme-lib: probe templates

Standard probe patterns for pleme-io services. Default shape: HTTP GET
on /healthz (liveness) + /readyz (readiness) — matches the Rust + Go
microservice convention.

For non-HTTP workloads (mysql, rabbitmq, redis, etc.) override:
  health:
    type: TCPSocket   # default is HTTPGet
    port: amqp
    # OR
    type: Exec
    execCommand: ["mysqladmin", "ping", "-h", "localhost"]

The `type` field selects the probe action; remaining timing knobs
(livenessInitialDelay, livenessPeriod, livenessFailureThreshold,
readinessInitialDelay, readinessPeriod, readinessFailureThreshold)
apply to every type.
*/}}

{{/*
Liveness probe
*/}}
{{- define "pleme-lib.livenessProbe" -}}
{{- $type := ((.Values.health).type) | default "HTTPGet" -}}
{{- if eq $type "TCPSocket" }}
tcpSocket:
  port: {{ (.Values.health).port | default "http" }}
{{- else if eq $type "Exec" }}
exec:
  command:
    {{- range (.Values.health).execCommand }}
    - {{ . | quote }}
    {{- end }}
{{- else }}
httpGet:
  path: {{ (.Values.health).path | default "/healthz" }}
  port: {{ (.Values.health).port | default "http" }}
{{- end }}
initialDelaySeconds: {{ (.Values.health).livenessInitialDelay | default 5 }}
periodSeconds: {{ (.Values.health).livenessPeriod | default 10 }}
failureThreshold: {{ (.Values.health).livenessFailureThreshold | default 3 }}
{{- end }}

{{/*
Readiness probe
*/}}
{{- define "pleme-lib.readinessProbe" -}}
{{- $type := ((.Values.health).type) | default "HTTPGet" -}}
{{- if eq $type "TCPSocket" }}
tcpSocket:
  port: {{ (.Values.health).port | default "http" }}
{{- else if eq $type "Exec" }}
exec:
  command:
    {{- range (.Values.health).execCommand }}
    - {{ . | quote }}
    {{- end }}
{{- else }}
httpGet:
  path: {{ (.Values.health).readyPath | default "/readyz" }}
  port: {{ (.Values.health).port | default "http" }}
{{- end }}
initialDelaySeconds: {{ (.Values.health).readinessInitialDelay | default 5 }}
periodSeconds: {{ (.Values.health).readinessPeriod | default 5 }}
failureThreshold: {{ (.Values.health).readinessFailureThreshold | default 2 }}
{{- end }}

{{/*
Startup probe (disabled by default)
*/}}
{{- define "pleme-lib.startupProbe" -}}
{{- if (.Values.startupProbe).enabled }}
httpGet:
  path: {{ (.Values.startupProbe).path | default "/healthz" }}
  port: {{ (.Values.startupProbe).port | default "http" }}
initialDelaySeconds: {{ (.Values.startupProbe).initialDelaySeconds | default 0 }}
periodSeconds: {{ (.Values.startupProbe).periodSeconds | default 5 }}
failureThreshold: {{ (.Values.startupProbe).failureThreshold | default 30 }}
{{- end }}
{{- end }}
