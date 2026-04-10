{{- define "pleme-nix-builder.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-nix-builder.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "pleme-nix-builder.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}

{{- define "pleme-nix-builder.selectorLabels" -}}
{{- include "pleme-lib.selectorLabels" . }}
{{- end }}
