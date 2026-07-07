{{/*
lareira-camelot-pitr helpers — labels + the HERMETIC-SUPPLY-CHAIN digest guard.
The guard mirrors the DISCIPLINE the team's chart already ships (fail the render on an
unpinned engine image); camelot adopts the discipline, it does not copy the file.
*/}}

{{- define "camelot-pitr.labels" -}}
app.kubernetes.io/name: lareira-camelot-pitr
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: camelot
camelot.pleme.io/surface: pitr
{{- end -}}

{{/* validateConfig — HERMETIC SUPPLY CHAIN: both engine artifacts MUST be @sha256-pinned. */}}
{{- define "camelot-pitr.validateConfig" -}}
{{- $img := (default dict .Values.images).pitrTools | default "" -}}
{{- if not $img -}}
  {{- fail "images.pitrTools is required — the drill-step Jobs (canary/verify/cleanup) run it; empty ⇒ no drill steps. Pin by @sha256 (HERMETIC SUPPLY CHAIN)." -}}
{{- end -}}
{{- if not (contains "@sha256:" $img) -}}
  {{- fail (printf "images.pitrTools=%q must be @sha256-pinned (HERMETIC SUPPLY CHAIN): a release must never resolve a moving tag. Pin the immutable digest read from ghcr.io/pleme-io/pitr-tools." $img) -}}
{{- end -}}
{{- $fn := (default dict .Values.function).package | default "" -}}
{{- $ref := (default dict .Values.function).ref | default "" -}}
{{- if not $fn -}}
  {{- fail "function.package is required — the Crossplane Composition references it as the drill engine; empty ⇒ nothing reconciles the CamelotPITRSession." -}}
{{- end -}}
{{- if not (contains "@sha256:" (printf "%s%s" $fn $ref)) -}}
  {{- fail (printf "function.package+ref must be @sha256-pinned (HERMETIC SUPPLY CHAIN); got %q%q. Pin the immutable digest read from ghcr.io/pleme-io/function-pitr-drill." $fn $ref) -}}
{{- end -}}
{{- end -}}
