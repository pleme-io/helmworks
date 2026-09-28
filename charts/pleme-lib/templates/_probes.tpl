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
livenessTimeout, readinessInitialDelay, readinessPeriod,
readinessFailureThreshold, readinessTimeout) apply to every type.

health.host (and startupProbe.host, defaulting to health.host) set the
address an httpGet/tcpSocket probe dials instead of the pod IP -- ADDED
2026-09-28 for a server that binds one address: on engenho's native
backend the pod IP is 127.0.0.1, and cid's llama-server binds its tailnet
address only, so every probe was refused and the startup probe killed a
healthy server every 15 minutes (47 restarts). Unset = the pod IP, as before.

livenessTimeout/readinessTimeout default to 1 (Kubernetes' own
probe.timeoutSeconds default when the field is omitted) -- ADDED
2026-07-24, this chart previously never rendered timeoutSeconds at
all, so every consumer was silently pinned to that 1s default with no
values-only escape hatch. Found live on pangea-operator:
an operator embedding a synchronous compiler/state-backend workload
can legitimately take >1s to answer a probe under a burst of
concurrent reconcile work without being unhealthy -- kubelet has no
way to know the difference between "busy" and "stuck" past a 1s
budget that tight. A workload whose probe handler can occasionally run
long now has a real, values-only way to say so.
*/}}

{{/*
Liveness probe
*/}}
{{- define "pleme-lib.livenessProbe" -}}
{{- $type := ((.Values.health).type) | default "HTTPGet" -}}
{{- if eq $type "TCPSocket" }}
tcpSocket:
  port: {{ (.Values.health).port | default "http" }}
  {{- with (.Values.health).host }}
  host: {{ . | quote }}
  {{- end }}
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
  {{- with (.Values.health).host }}
  host: {{ . | quote }}
  {{- end }}
{{- end }}
initialDelaySeconds: {{ (.Values.health).livenessInitialDelay | default 5 }}
periodSeconds: {{ (.Values.health).livenessPeriod | default 10 }}
timeoutSeconds: {{ (.Values.health).livenessTimeout | default 1 }}
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
  {{- with (.Values.health).host }}
  host: {{ . | quote }}
  {{- end }}
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
  {{- with (.Values.health).host }}
  host: {{ . | quote }}
  {{- end }}
{{- end }}
initialDelaySeconds: {{ (.Values.health).readinessInitialDelay | default 5 }}
periodSeconds: {{ (.Values.health).readinessPeriod | default 5 }}
timeoutSeconds: {{ (.Values.health).readinessTimeout | default 1 }}
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
  {{- with ((.Values.startupProbe).host | default (.Values.health).host) }}
  host: {{ . | quote }}
  {{- end }}
initialDelaySeconds: {{ (.Values.startupProbe).initialDelaySeconds | default 0 }}
periodSeconds: {{ (.Values.startupProbe).periodSeconds | default 5 }}
failureThreshold: {{ (.Values.startupProbe).failureThreshold | default 30 }}
{{- end }}
{{- end }}
