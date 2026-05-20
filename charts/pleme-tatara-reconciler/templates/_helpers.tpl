{{/* Wrapper-chart helpers — defer to pleme-lib via the operator subchart's
     context. Indexed lookup because `pleme-operator` has a `-` in the name
     (Go template attribute access disallows dashes; `index` is the typed
     escape hatch.) */}}
{{- define "pleme-tatara-reconciler.fullname" -}}
{{- include "pleme-lib.fullname" (index .Subcharts "pleme-operator") -}}
{{- end -}}

{{- define "pleme-tatara-reconciler.labels" -}}
{{- include "pleme-lib.labels" (index .Subcharts "pleme-operator") -}}
{{- end -}}
