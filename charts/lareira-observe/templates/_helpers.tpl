{{/*
lareira-observe — helpers for the ATTACH abstraction.

This chart owns no workload of its own; every helper is parameterised by the
EXTERNAL target (target.*), NOT by the lareira-observe release identity. The
pleme-lib name/namespace/selectorLabels helpers all derive from .Release.* and
the chart's own identity, so they are deliberately NOT used to build the
ServiceMonitor selector or the band targetRef — those must point at the target.
*/}}

{{/*
lareira-observe.targetName — REQUIRED. fail()s with a clear message when unset.
This is the single load-bearing input; every other helper depends on it.
*/}}
{{- define "lareira-observe.targetName" -}}
{{- $n := (.Values.target).name | default "" -}}
{{- if eq $n "" -}}
{{- fail "lareira-observe: target.name is REQUIRED — it names the in-cluster workload/Service this release attaches to (e.g. pangea-operator)" -}}
{{- end -}}
{{- $n -}}
{{- end -}}

{{/*
lareira-observe.fullname — the release-side name for the resources this chart
emits (ServiceMonitor / PrometheusRule / AlertmanagerConfig). Disambiguated by
the target so two releases attaching to two targets in one namespace don't clash.
*/}}
{{- define "lareira-observe.fullname" -}}
{{- printf "observe-%s" (include "lareira-observe.targetName" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
lareira-observe.targetNamespace — the namespace the TARGET lives in. Defaults to
the release namespace. This is what the ServiceMonitor namespaceSelector matches
and where the bands are placed.
*/}}
{{- define "lareira-observe.targetNamespace" -}}
{{- (.Values.target).namespace | default .Release.Namespace -}}
{{- end -}}

{{/*
lareira-observe.targetDeployment — the Deployment name the breathe bands carve.
Defaults to target.name.
*/}}
{{- define "lareira-observe.targetDeployment" -}}
{{- (.Values.target).deployment | default (include "lareira-observe.targetName" .) -}}
{{- end -}}

{{/*
lareira-observe.labels — standard metadata on every emitted resource. Identifies
the attach relationship (which target) so operators can find every attachment
for a given workload.
*/}}
{{- define "lareira-observe.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nexus-platform
lareira.pleme.io/observe-target: {{ include "lareira-observe.targetName" . | quote }}
{{- end -}}

{{/*
lareira-observe.targetSelector — the matchLabels selecting the TARGET Service for
scraping. Honours target.labelSelector when set; otherwise falls back to the
pleme-lib `app: <target.name>` convention.
*/}}
{{- define "lareira-observe.targetSelector" -}}
{{- $sel := (.Values.target).labelSelector | default dict -}}
{{- if $sel -}}
{{- toYaml $sel -}}
{{- else -}}
app: {{ include "lareira-observe.targetName" . }}
{{- end -}}
{{- end -}}

{{/*
lareira-observe.breatheTargetRef — the EXTERNAL targetRef the bands carve.
Honours breathe.targetRef when set (e.g. a CNPG Cluster); otherwise wires it
from target.* as an apps/v1 Deployment named target.deployment.
*/}}
{{- define "lareira-observe.breatheTargetRef" -}}
{{- $ref := (.Values.breathe).targetRef | default dict -}}
{{- if $ref -}}
{{- toYaml $ref -}}
{{- else -}}
apiVersion: apps/v1
kind: Deployment
name: {{ include "lareira-observe.targetDeployment" . }}
{{- end -}}
{{- end -}}
