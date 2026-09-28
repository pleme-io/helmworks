{{/*
llama-server's arguments, derived from .Values.model, .Values.server and
.Values.draft, then .Values.extraArgs. Every value is quoted: container args
are strings.
*/}}
{{- define "pleme-llama-server.args" -}}
- "-m"
- {{ .Values.model.path | quote }}
- "--alias"
- {{ .Values.model.alias | quote }}
- "--host"
- {{ .Values.server.host | quote }}
- "--port"
- {{ .Values.server.port | quote }}
- "-c"
- {{ .Values.server.contextSize | quote }}
- "-ngl"
- {{ .Values.server.gpuLayers | quote }}
- "--flash-attn"
- {{ .Values.server.flashAttn | quote }}
- "--cache-type-k"
- {{ .Values.server.cacheTypeK | quote }}
- "--cache-type-v"
- {{ .Values.server.cacheTypeV | quote }}
- "--parallel"
- {{ .Values.server.parallel | quote }}
- "--cache-reuse"
- {{ .Values.server.cacheReuse | quote }}
{{- if .Values.server.jinja }}
- "--jinja"
{{- end }}
{{- if .Values.server.metrics }}
- "--metrics"
{{- end }}
{{- if .Values.draft.path }}
- "--model-draft"
- {{ .Values.draft.path | quote }}
{{- end }}
{{- range .Values.extraArgs }}
- {{ . | quote }}
{{- end }}
{{- end -}}

{{/*
The container environment: HOME when set (the native backend clears the
environment), then .Values.env.
*/}}
{{- define "pleme-llama-server.env" -}}
{{- $env := list -}}
{{- if .Values.home -}}
{{- $env = append $env (dict "name" "HOME" "value" .Values.home) -}}
{{- end -}}
{{- range .Values.env -}}
{{- $env = append $env . -}}
{{- end -}}
{{- toYaml $env -}}
{{- end -}}
