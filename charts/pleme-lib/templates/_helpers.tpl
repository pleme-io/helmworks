{{/*
pleme-lib: shared helpers for all pleme-io charts
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "pleme-lib.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this.
If release name contains chart name it will be used as a full name.
*/}}
{{- define "pleme-lib.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pleme-lib.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Render a K8s-label-safe image version. K8s labels are constrained
to ≤63 chars, must start+end with alphanumeric, and may contain
`-`, `_`, `.`. SHA digests (e.g. `sha256:73c2…488158`) are 71 chars
and contain a `:`, so feeding `image.tag` straight into
`app.kubernetes.io/version` rejects every digest-pinned chart at
admission. Sanitize: prefer image.digest (substrate-canonical),
trim a `sha256:` prefix, truncate to 63.
*/}}
{{- define "pleme-lib.versionLabel" -}}
{{- $img := .Values.image | default dict -}}
{{- $raw := $img.digest | default "" | toString -}}
{{- if eq $raw "" -}}
  {{- $raw = $img.tag | default .Chart.AppVersion | toString -}}
{{- end -}}
{{- $stripped := trimPrefix "sha256:" $raw -}}
{{- if eq $stripped "" -}}{{- $stripped = "unknown" -}}{{- end -}}
{{- $stripped | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pleme-lib.labels" -}}
helm.sh/chart: {{ include "pleme-lib.chart" . }}
{{ include "pleme-lib.selectorLabels" . }}
app: {{ include "pleme-lib.fullname" . }}
app.kubernetes.io/version: {{ include "pleme-lib.versionLabel" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nexus-platform
{{- $cl := include "pleme-lib.compliance.labels" . | trim }}
{{- if $cl }}
{{ $cl }}
{{- end }}
{{- with .Values.additionalLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pleme-lib.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pleme-lib.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "pleme-lib.serviceAccountName" -}}
{{- if (.Values.serviceAccount).create }}
{{- default (include "pleme-lib.fullname" .) (.Values.serviceAccount).name }}
{{- else }}
{{- default "default" (.Values.serviceAccount).name }}
{{- end }}
{{- end }}

{{/*
Namespace
*/}}
{{- define "pleme-lib.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Prometheus scrape annotations
*/}}
{{- define "pleme-lib.prometheusAnnotations" -}}
{{- if (.Values.monitoring).enabled }}
prometheus.io/scrape: "true"
prometheus.io/port: {{ (.Values.monitoring).port | default "8080" | quote }}
prometheus.io/path: {{ (.Values.monitoring).path | default "/metrics" | quote }}
{{- end }}
{{- end }}

{{/*
Image string.

Tag resolution chain (first non-empty wins):
  1. `.Values.image.tag` — explicit per-chart override (preferred for
     production, set by FluxCD HelmRelease patches)
  2. `.Chart.AppVersion` — sensible chart-author default; tracks the
     consuming chart's release version automatically
  3. `"latest"` — final fallback (mostly for dev/test renders where
     neither is set)

Charts that pin `image.tag` explicitly are unchanged. Charts that
leave `image.tag: ""` previously rendered `repo:latest` and now
render `repo:{Chart.AppVersion}` — matches the pre-pleme-lib
hand-authored helper convention every existing chart used.
*/}}
{{- define "pleme-lib.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion | default "latest" -}}
{{- printf "%s:%s" .Values.image.repository $tag }}
{{- end }}

{{/*
Istio sidecar annotations for pod templates
*/}}
{{- define "pleme-lib.istioAnnotations" -}}
{{- if (.Values.istio).enabled }}
sidecar.istio.io/inject: {{ (.Values.istio).inject | default true | quote }}
{{- with (.Values.istio).excludeOutboundPorts }}
traffic.sidecar.istio.io/excludeOutboundPorts: {{ . | quote }}
{{- end }}
{{- with (.Values.istio).excludeInboundPorts }}
traffic.sidecar.istio.io/excludeInboundPorts: {{ . | quote }}
{{- end }}
{{- if (.Values.istio).holdApplicationUntilProxyStarts }}
proxy.istio.io/config: '{"holdApplicationUntilProxyStarts": true}'
{{- end }}
{{- end }}
{{- end }}

{{/*
FluxCD prune disabled annotation — prevents FluxCD from deleting the resource
Used for StatefulSet VCTs, database CRs, cache PVCs.
*/}}
{{- define "pleme-lib.fluxcdPruneDisabled" -}}
kustomize.toolkit.fluxcd.io/prune: disabled
{{- end }}

{{/*
Attestation annotations for sekiban integrity verification.
Produces sekiban.pleme.io/* annotations when attestation hashes are configured.
These annotations are verified by sekiban's ValidatingAdmissionWebhook.

Values:
  attestation.signature       — master signature (blake3:hex)
  attestation.certificationHash — product certification hash (blake3:hex)
  attestation.complianceHash  — compliance test result hash (blake3:hex)
  attestation.changesetHash   — changeset integrity hash (blake3:hex)
*/}}
{{- define "pleme-lib.attestationAnnotations" -}}
{{- if (.Values.attestation).enabled }}
{{- with (.Values.attestation).signature }}
sekiban.pleme.io/signature: {{ . | quote }}
{{- end }}
{{- with (.Values.attestation).certificationHash }}
sekiban.pleme.io/certification-hash: {{ . | quote }}
{{- end }}
{{- with (.Values.attestation).complianceHash }}
sekiban.pleme.io/compliance-hash: {{ . | quote }}
{{- end }}
{{- with (.Values.attestation).changesetHash }}
sekiban.pleme.io/changeset-hash: {{ . | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
All resource-level annotations (metadata.annotations on Deployment, Service, etc.).

pleme-lib 0.9.0+: annotations dispatch through the overlay registry.
Each registered overlay's `annotations` surface fires in order; the
output is concatenated. Adding a new regime is one new overlay file —
this helper does not need editing.

Surfaces, in dispatch order:
  1. attestationAnnotations  — sekiban hashes (legacy, pre-overlay)
  2. compliance.annotations  — baseline / framework / enforce metadata
  3. compliance.audit.annotations — audit pipeline metadata
  4. overlay.dispatchAll annotations — every applied overlay
  5. .Values.annotations     — consumer overrides
*/}}
{{- define "pleme-lib.resourceAnnotations" -}}
{{- include "pleme-lib.attestationAnnotations" . }}
{{- include "pleme-lib.compliance.annotations" . }}
{{- include "pleme-lib.compliance.audit.annotations" . }}
{{- /* Overlay annotations are guaranteed-newline-separated via the
       intentional blank line below. Without this, the audit helper
       (which trims trailing whitespace) collides with the first overlay
       annotation on the same line. */ -}}
{{ include "pleme-lib.overlay.dispatchAll" (list "annotations" .) }}
{{- with .Values.annotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Image string with compliance-aware rendering. Three input shapes accepted:
  1. .Values.image.repository contains "@sha256:..."   -> use repo as-is
  2. .Values.image.digest is set (sha256:...)           -> "repo@digest"
  3. .Values.image.tag starts with "sha256:"            -> "repo@tag"
  4. fallback                                           -> "repo:tag"
Only forms 1-3 are accepted at compliance baseline >= fedramp-high.
*/}}
{{- define "pleme-lib.compliance.image" -}}
{{- $repo := .Values.image.repository | toString -}}
{{- /* Same fallback chain as pleme-lib.image — explicit tag wins, then
       chart AppVersion, then "latest". Keeps both helpers in sync. */ -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion | default "latest" | toString -}}
{{- $digest := .Values.image.digest | default "" | toString -}}
{{- if contains "@sha256:" $repo -}}
{{- $repo -}}
{{- else if hasPrefix "sha256:" $digest -}}
{{- printf "%s@%s" $repo $digest -}}
{{- else if hasPrefix "sha256:" $tag -}}
{{- printf "%s@%s" $repo $tag -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end }}
