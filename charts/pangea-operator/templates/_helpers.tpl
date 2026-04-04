{{/*
pangea-operator helpers — delegates to pleme-lib + executor env injection
*/}}

{{- define "pangea-operator.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "pangea-operator.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{/*
Generate executor environment variables from the executor config section.
These are injected into the operator container alongside user-provided env vars.
*/}}
{{- define "pangea-operator.executorEnv" -}}
- name: TOFU_BINARY
  value: {{ .Values.executor.tofu.binary | quote }}
- name: PANGEA_TIMEOUT
  value: {{ .Values.executor.tofu.timeout | quote }}
- name: PACKER_BINARY
  value: {{ .Values.executor.packer.binary | quote }}
- name: PACKER_TIMEOUT
  value: {{ .Values.executor.packer.timeout | quote }}
- name: PANGEA_WORKSPACE_BASE
  value: {{ .Values.executor.workspaceBase | quote }}
- name: COMPILER_ENDPOINT
  value: {{ .Values.compilerEndpoint | quote }}
{{- if .Values.executor.verbose }}
- name: PANGEA_VERBOSE
  value: "true"
{{- end }}
{{- end }}
