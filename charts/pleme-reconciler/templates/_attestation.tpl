{{/*
pleme-reconciler.attestationLabels

Renders magma-bundle attestation labels (bundle_id, plan_id, kind)
on a resource. Other charts include these labels on Deployments,
Services, ConfigMaps so a ValidatingAdmissionWebhook can verify
bundle attestation pre-apply.

Always rendered; emits an empty fragment when
`reconciler.attestation.enabled: false`. Designed to be used
inside `labels:` blocks via:

  metadata:
    labels:
      …
      {{- include "pleme-reconciler.attestationLabels" . | nindent 4 }}

Per theory/CONVERGENCE-SUBSTRATE.md §IV.3.
*/}}
{{- define "pleme-reconciler.attestationLabels" -}}
{{- $att := .Values.reconciler.attestation | default dict -}}
{{- if $att.enabled }}
{{- $kind := $att.kind | default (.Values.reconciler.kind | default (printf "%s" .Chart.Name)) -}}
magma.pleme.io/bundle_id: {{ $att.bundleId | default "" | quote }}
magma.pleme.io/plan_id:   {{ $att.planId   | default "" | quote }}
magma.pleme.io/kind:      {{ $kind | quote }}
{{- end }}
{{- end }}
