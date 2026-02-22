{{/*
pleme-migration helpers — delegates to pleme-lib
*/}}

{{- define "pleme-migration.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-migration.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}
