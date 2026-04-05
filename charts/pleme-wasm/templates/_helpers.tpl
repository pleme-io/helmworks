{{/*
pleme-wasm helpers — delegates to pleme-lib
*/}}

{{- define "pleme-wasm.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-wasm.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
