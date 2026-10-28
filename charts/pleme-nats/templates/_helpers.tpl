{{/*
pleme-nats helpers — delegates name/labels to pleme-lib.
*/}}

{{- define "pleme-nats.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pleme-nats.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "pleme-nats.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}

{{- define "pleme-nats.selectorLabels" -}}
{{- include "pleme-lib.selectorLabels" . }}
{{- end }}

{{- define "pleme-nats.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pleme-nats.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
URL the in-cluster client uses to reach this NATS deployment.
Used by tend-throttle / shinryu / vector via Helm value cross-refs.
*/}}
{{- define "pleme-nats.clientUrl" -}}
nats://{{ include "pleme-nats.fullname" . }}.{{ .Release.Namespace }}.svc:{{ .Values.service.ports.client }}
{{- end }}

{{/*
HTTP monitoring endpoint (host:port form, no scheme). KEDA's
nats-jetstream trigger expects this exact shape.
*/}}
{{- define "pleme-nats.monitoringEndpoint" -}}
{{ include "pleme-nats.fullname" . }}.{{ .Release.Namespace }}.svc:{{ .Values.service.ports.monitoring }}
{{- end }}

{{- define "pleme-nats.closure" -}}
{{- $ref := toString . -}}
{{- if not (hasPrefix "nix:/nix/store/" $ref) -}}{{- "" -}}{{- else -}}{{- trimPrefix "nix:" $ref | splitList ":" | first -}}{{- end -}}
{{- end }}

{{- define "pleme-nats.validate" -}}
{{- if not (has .Values.runtime (list "oci" "native")) }}
{{- fail (printf "pleme-nats: runtime=%q is not one of oci|native" (toString .Values.runtime)) }}
{{- end }}
{{- if and .Values.server.auth.enabled (not .Values.server.auth.secretName) }}
{{- fail "pleme-nats: server.auth.enabled needs server.auth.secretName, a Secret holding the user and password keys" }}
{{- end }}
{{- if eq .Values.runtime "native" }}
{{- if not (include "pleme-nats.closure" .Values.image.repository) }}
{{- fail "pleme-nats: runtime native needs image.repository = nix:/nix/store/<nats-server closure>" }}
{{- end }}
{{- if and .Values.exporter.enabled (not (include "pleme-nats.closure" .Values.exporter.image.repository)) }}
{{- fail "pleme-nats: runtime native needs exporter.image.repository = nix:/nix/store/<prometheus-nats-exporter closure>, or exporter.enabled false" }}
{{- end }}
{{- if not (hasPrefix "/" (toString .Values.server.jetstream.storeDir)) }}
{{- fail "pleme-nats: runtime native needs server.jetstream.storeDir as an absolute host path" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "pleme-nats.authEnv" -}}
{{- if .Values.server.auth.enabled }}
- name: NATS_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.server.auth.secretName }}
      key: {{ .Values.server.auth.userKey }}
- name: NATS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.server.auth.secretName }}
      key: {{ .Values.server.auth.passwordKey }}
{{- end }}
{{- end }}

{{- define "pleme-nats.nativeArgs" -}}
{{- $args := list "--addr" (toString .Values.server.host) "--port" (toString .Values.server.port) "--http_port" (toString .Values.server.monitoringPort) "--server_name" "$(POD_NAME)" -}}
{{- if .Values.server.jetstream.enabled }}
{{- $args = concat $args (list "--jetstream" "--store_dir" (toString .Values.server.jetstream.storeDir)) -}}
{{- end }}
{{- if .Values.server.auth.enabled }}
{{- $args = concat $args (list "--user" "$(NATS_USER)" "--pass" "$(NATS_PASSWORD)") -}}
{{- end }}
{{- toYaml $args }}
{{- end }}
