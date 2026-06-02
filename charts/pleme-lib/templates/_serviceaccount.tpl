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

{{/*
pleme-lib.serviceAccounts — multiple ServiceAccounts from a .Values.serviceAccounts map
(sibling of the single-SA pleme-lib.serviceaccount; same map-iter idiom as rbac /
externalsecret / configmaps). The map key is the SA name verbatim, so it matches what a
DeploymentRuntimeConfig / RBAC subject references. No-op when the map is empty/absent.

  serviceAccounts:
    <name>:
      # namespace: <ns>          # defaults to release namespace
      # annotations: { eks.amazonaws.com/role-arn: <arn> }
      # automountServiceAccountToken: false
*/}}
{{- define "pleme-lib.serviceAccounts" -}}
{{- range $name, $spec := .Values.serviceAccounts }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $name }}
  namespace: {{ $spec.namespace | default (include "pleme-lib.namespace" $) }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with $spec.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- if hasKey ($spec | default dict) "automountServiceAccountToken" }}
automountServiceAccountToken: {{ $spec.automountServiceAccountToken }}
{{- end }}
{{- end }}
{{- end }}
