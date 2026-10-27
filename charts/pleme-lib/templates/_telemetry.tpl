{{- define "pleme-lib.kenshi-labels" -}}
{{- $k := .Values.kenshi | default dict -}}
{{- if and $k (or (not (hasKey $k "enabled")) $k.enabled) -}}
kenshi.pleme.io/service: {{ $k.service | default (include "pleme-lib.fullname" .) | trunc 63 | trimSuffix "-" | quote }}
{{- with $k.product }}
kenshi.pleme.io/product: {{ . | trunc 63 | trimSuffix "-" | quote }}
{{- end }}
{{- with $k.environment }}
kenshi.pleme.io/environment: {{ . | trunc 63 | trimSuffix "-" | quote }}
{{- end }}
{{- end -}}
{{- end }}

{{- define "pleme-lib.telemetry-endpoint" -}}
{{- $signal := index . 0 -}}
{{- $s := index . 1 | default dict -}}
{{- if and $s.endpoint (or (not (hasKey $s "enabled")) $s.enabled) -}}
{{- if not (regexMatch "^https?://[^ ]+$" $s.endpoint) -}}
{{- fail (printf "telemetry.%s.endpoint must be an http:// or https:// url, got %q" $signal $s.endpoint) -}}
{{- end -}}
{{- $s.endpoint -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.telemetry-export" -}}
{{- $t := .Values.telemetry | default dict -}}
{{- $out := list -}}
{{- with include "pleme-lib.telemetry-endpoint" (list "logs" $t.logs) -}}
{{- $out = append $out (dict "name" "VECTOR_ENDPOINT" "value" .) -}}
{{- end -}}
{{- with include "pleme-lib.telemetry-endpoint" (list "traces" $t.traces) -}}
{{- $out = append $out (dict "name" "OTEL_EXPORTER_OTLP_ENDPOINT" "value" .) -}}
{{- $out = append $out (dict "name" "OTEL_SERVICE_NAME" "value" (($t.traces).serviceName | default (include "pleme-lib.fullname" $))) -}}
{{- end -}}
{{- with $out -}}{{- toYaml . -}}{{- end -}}
{{- end }}
