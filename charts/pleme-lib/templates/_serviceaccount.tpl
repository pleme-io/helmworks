{{/*
pleme-lib: serviceaccount named template

At compliance baseline >= fedramp-moderate, sets
`automountServiceAccountToken: false` on the ServiceAccount itself (AC-6),
so any pod that doesn't explicitly opt back in inherits the safe default.
*/}}

{{- define "pleme-lib.serviceaccount" -}}
{{- if (.Values.serviceAccount).create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "pleme-lib.serviceAccountName" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  {{- $cAnnot := include "pleme-lib.compliance.annotations" . | trim }}
  {{- if or (.Values.serviceAccount).annotations $cAnnot }}
  annotations:
    {{- with (.Values.serviceAccount).annotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- if $cAnnot }}
    {{- $cAnnot | nindent 4 }}
    {{- end }}
  {{- end }}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") }}
{{- if eq $atLeastMod "true" }}
automountServiceAccountToken: {{ (.Values.serviceAccount).automountServiceAccountToken | default false }}
{{- else if hasKey ((.Values.serviceAccount) | default dict) "automountServiceAccountToken" }}
automountServiceAccountToken: {{ (.Values.serviceAccount).automountServiceAccountToken }}
{{- end }}
{{- end }}
{{- end }}
