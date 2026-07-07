{{- define "lareira-sui.labels" -}}
app.kubernetes.io/name: lareira-sui
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: lareira-sui-{{ .Chart.Version }}
pleme.io/component: super-cache-ci
{{- end -}}

{{/* Minimal, immutable selector labels (never version-bearing — selectors are
     immutable on Deployment/StatefulSet). Component is appended at each callsite. */}}
{{- define "lareira-sui.selectorLabels" -}}
app.kubernetes.io/name: lareira-sui
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Derived Redis L1 URL (override via .Values.tiered.l1.url). */}}
{{- define "lareira-sui.l1url" -}}
{{- if .Values.tiered.l1.url -}}
{{- .Values.tiered.l1.url -}}
{{- else -}}
redis://{{ .Values.redis.service.name }}:{{ .Values.redis.service.port }}
{{- end -}}
{{- end -}}

{{/* Derived Postgres L2 DSN (override via .Values.tiered.l2.url). Carries the
     L2 password → rendered ONLY into the sui-tiered-backend Secret. */}}
{{- define "lareira-sui.l2url" -}}
{{- if .Values.tiered.l2.url -}}
{{- .Values.tiered.l2.url -}}
{{- else -}}
postgres://{{ .Values.postgres.auth.user }}:{{ .Values.postgres.auth.password }}@{{ .Values.postgres.service.name }}:{{ .Values.postgres.service.port }}/{{ .Values.postgres.auth.database }}
{{- end -}}
{{- end -}}

{{/* The full tiered BackendConfig TOML (sui_cache::BackendConfig::Tiered). */}}
{{- define "lareira-sui.backendToml" -}}
type = "tiered"
write_policy = {{ .Values.tiered.writePolicy | quote }}

  [l1]
  type = "redis"
  url = {{ include "lareira-sui.l1url" . | quote }}

  [l2]
  type = "pg"
  url = {{ include "lareira-sui.l2url" . | quote }}
  max_conns = {{ .Values.tiered.l2.maxConns }}

  [l3]
{{- if eq .Values.tiered.l3.kind "s3" }}
  type = "s3"
  bucket = {{ .Values.tiered.l3.s3.bucket | quote }}
  region = {{ .Values.tiered.l3.s3.region | quote }}
{{- if .Values.tiered.l3.s3.endpoint }}
  endpoint = {{ .Values.tiered.l3.s3.endpoint | quote }}
{{- end }}
{{- else }}
  type = "local"
  path = {{ .Values.tiered.l3.path | quote }}
{{- end }}
{{- end -}}
