{{/*
supacharge-cache umbrella helpers.

The umbrella owns three of its own resources (the rest is subchart composition):
  - its own namespace stamp (namespace.yaml),
  - the SupachargeNodeGroup InfrastructureTemplate (infratemplate.yaml),
  - a SUSPENDED Flux Kustomization (flux-kustomization.yaml).
Every generic name/label helper delegates to pleme-lib (never re-rolled).
*/}}

{{- define "supacharge-cache.name" -}}
{{- include "pleme-lib.name" . }}
{{- end }}

{{- define "supacharge-cache.fullname" -}}
{{- include "pleme-lib.fullname" . }}
{{- end }}

{{- define "supacharge-cache.labels" -}}
{{- include "pleme-lib.labels" . }}
{{- end }}
