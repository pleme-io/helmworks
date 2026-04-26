{{/*
pleme-discord-bot helpers — delegate to pleme-lib + chart-specific helpers
*/}}

{{- define "pleme-discord-bot.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-discord-bot.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{/*
Resolve the token Secret name. Defaults to `discord-<botName>-token`
when not explicitly overridden.
*/}}
{{- define "pleme-discord-bot.tokenSecretName" -}}
{{- if .Values.tokenSecret.name -}}
{{- .Values.tokenSecret.name -}}
{{- else -}}
{{- printf "discord-%s-token" .Values.botName -}}
{{- end -}}
{{- end }}

{{/*
Validate required values up-front. Helm 3 errors with the message we
embed when the template fails to render — so make these bot configuration
omissions visible before the cluster ever sees a half-baked Deployment.
*/}}
{{- define "pleme-discord-bot.validate" -}}
{{- if not .Values.botName -}}
{{- fail "pleme-discord-bot: .Values.botName is required (must match Bot::NAME of the deployed bot crate)" -}}
{{- end -}}
{{- if not .Values.image.repository -}}
{{- fail "pleme-discord-bot: .Values.image.repository is required" -}}
{{- end -}}
{{- end }}
