{{/*
pleme-lib: VictoriaMetrics CRD family — the abstracted VM workload surface.

The VM operator is the controller; the WORKLOAD is declared as VM CRDs. This
file is the named-template family (peer of _crossplane.tpl) that lets a chart
synthesize the full VM surface from a typed `.Values.vm.*` border — every CR
flowing through pleme-lib so labels + attestation/resourceAnnotations apply by
construction, exactly as pleme-vector synthesizes Vector config.

Each template: no-op on empty/absent map; composes pleme-lib.labels +
resourceAnnotations; spec is a typed passthrough of the user's map (operator
owns the rich validation); the WHAT (per-component values) is decoupled from
the HOW (the operator reconciles it). Mirrors the proven pleme-lib.vmServiceScrape
idiom. apiVersion overridable per call via `.apiVersion`.

Workload CRDs:  vmSingle vmCluster vmAgent vmAlert vmAlertmanager vmAuth
Config CRDs:    vmRule vmAlertmanagerConfig vmPodScrape vmNodeScrape
                (vmServiceScrape already lives in _vmservicescrape.tpl)

Values shape (illustrative):
  vm:
    apiVersion: operator.victoriametrics.com/v1beta1   # family default
    single:        { enabled: true, retentionPeriod: 14d, storage: {...}, resources: {...} }
    agent:         { enabled: true, selectAllByDefault: true, ... }
    alert:         { enabled: true, ... }
    alertmanager:  { enabled: true, ... }
    auth:          { enabled: false, ... }
    cluster:       { enabled: false, ... }
    rules:         { enabled: true, groups: [...] }              # → VMRule
    alertmanagerConfig: { enabled: true, spec: {...} }           # → VMAlertmanagerConfig
    podScrapes:    { web: { enabled: true, ... } }               # map → N VMPodScrape
    nodeScrapes:   { node: { enabled: true, ... } }              # map → N VMNodeScrape
*/}}

{{/* internal: family apiVersion */}}
{{- define "pleme-lib._vm.apiVersion" -}}
{{- (.Values.vm).apiVersion | default "operator.victoriametrics.com/v1beta1" -}}
{{- end -}}

{{/* internal: standard metadata block for a VM CR.
   arg = (dict "ctx" $ "name" "<suffix>" "fullName" "<verbatim>")
   - fullName (optional): the EXACT metadata.name, verbatim. Use when a CR must
     adopt an operator-derived resource that already exists under a specific
     name (the no-op-migration case — the VM operator keys its StatefulSet/
     Deployment/Service/PVC off the CR name, so matching the name keeps the
     existing data + service-DNS). Set per component via `vm.<kind>.name`.
   - name (optional): a suffix appended to the chart fullname (the default
     multi-CR disambiguator, e.g. "-agent"). Ignored when fullName is set. */}}
{{- define "pleme-lib._vm.metadata" -}}
{{- $ctx := .ctx -}}
metadata:
  name: {{ if .fullName }}{{ .fullName }}{{ else }}{{ include "pleme-lib.fullname" $ctx }}{{ if .name }}-{{ .name }}{{ end }}{{ end }}
  namespace: {{ include "pleme-lib.namespace" $ctx }}
  labels:
    {{- include "pleme-lib.labels" $ctx | nindent 4 }}
  {{- $resAnnotations := include "pleme-lib.resourceAnnotations" $ctx }}
  {{- if $resAnnotations }}
  annotations:
    {{- $resAnnotations | nindent 4 }}
  {{- end }}
{{- end -}}

{{/* ── VMSingle — the metric store ──────────────────────────────────────
   Storage invariant (the rio-bug-prevention): a custom storageDataPath WITHOUT
   a matching `storage` PVC (or raw `volumes`) is what the operator admission
   webhook rejects ("spec.volumes must have at least 1 value"), which left rio
   with NO metric store. We make that state UNREPRESENTABLE: fail() at render
   if storageDataPath is set without storage/volumes. The common case (storage
   PVC, no custom path → operator mounts at its default) renders clean. */}}
{{- define "pleme-lib.vmSingle" -}}
{{- with (.Values.vm).single }}
{{- if .enabled }}
{{- if and .storageDataPath (not (or .storage .volumes)) }}
{{- fail "pleme-lib.vmSingle: vm.single.storageDataPath is set without a matching `storage` (PVC) or `volumes` — the VM-operator admission webhook rejects this (no volume at the custom path). Provide `storage:` (a PVC) or drop storageDataPath to use the operator default path." }}
{{- end }}
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMSingle
{{- include "pleme-lib._vm.metadata" (dict "ctx" $ "fullName" .name) | nindent 0 }}
spec:
  {{- toYaml (omit . "enabled" "name") | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── VMCluster — vminsert/vmselect/vmstorage (HA topology) ── */}}
{{- define "pleme-lib.vmCluster" -}}
{{- with (.Values.vm).cluster }}
{{- if .enabled }}
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMCluster
{{- include "pleme-lib._vm.metadata" (dict "ctx" $ "fullName" .name) | nindent 0 }}
spec:
  {{- toYaml (omit . "enabled" "name") | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── VMAgent — scrape + remote-write ── */}}
{{- define "pleme-lib.vmAgent" -}}
{{- with (.Values.vm).agent }}
{{- if .enabled }}
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMAgent
{{- include "pleme-lib._vm.metadata" (dict "ctx" $ "name" "agent" "fullName" .name) | nindent 0 }}
spec:
  {{- toYaml (omit . "enabled" "name") | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── VMAlert — evaluate VMRule/PrometheusRule → Alertmanager ── */}}
{{- define "pleme-lib.vmAlert" -}}
{{- with (.Values.vm).alert }}
{{- if .enabled }}
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMAlert
{{- include "pleme-lib._vm.metadata" (dict "ctx" $ "name" "alert" "fullName" .name) | nindent 0 }}
spec:
  {{- toYaml (omit . "enabled" "name") | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── VMAlertmanager — alert routing ── */}}
{{- define "pleme-lib.vmAlertmanager" -}}
{{- with (.Values.vm).alertmanager }}
{{- if .enabled }}
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMAlertmanager
{{- include "pleme-lib._vm.metadata" (dict "ctx" $ "fullName" .name) | nindent 0 }}
spec:
  {{- toYaml (omit . "enabled" "name") | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── VMAuth — auth proxy / multi-tenant routing ── */}}
{{- define "pleme-lib.vmAuth" -}}
{{- with (.Values.vm).auth }}
{{- if .enabled }}
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMAuth
{{- include "pleme-lib._vm.metadata" (dict "ctx" $ "fullName" .name) | nindent 0 }}
spec:
  {{- toYaml (omit . "enabled" "name") | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── VMRule — typed alert rules (the WHAT; severity-labelled) ──
   Moves alert definitions out of hand-authored PrometheusRule YAML into a
   native operator CR. `groups` passes through; everything else is metadata. */}}
{{- define "pleme-lib.vmRule" -}}
{{- with (.Values.vm).rules }}
{{- if .enabled }}
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMRule
{{- include "pleme-lib._vm.metadata" (dict "ctx" $) | nindent 0 }}
spec:
  {{- if not .groups }}{{- fail "pleme-lib.vmRule: vm.rules.enabled requires non-empty `groups`" }}{{- end }}
  groups:
    {{- toYaml .groups | nindent 4 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── VMAlertmanagerConfig — the routing tree (ntfy receivers per severity) ──
   Moves the hand-authored alertmanager routing.yaml into a chart-rendered CR. */}}
{{- define "pleme-lib.vmAlertmanagerConfig" -}}
{{- with (.Values.vm).alertmanagerConfig }}
{{- if .enabled }}
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMAlertmanagerConfig
{{- include "pleme-lib._vm.metadata" (dict "ctx" $) | nindent 0 }}
spec:
  {{- if not .spec }}{{- fail "pleme-lib.vmAlertmanagerConfig: vm.alertmanagerConfig.enabled requires a `spec` (route + receivers)" }}{{- end }}
  {{- toYaml .spec | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── VMPodScrape (map → N) — first-class peer of vmServiceScrape ── */}}
{{- define "pleme-lib.vmPodScrape" -}}
{{- range $name, $cfg := (.Values.vm).podScrapes }}
{{- if $cfg.enabled }}
---
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMPodScrape
{{- include "pleme-lib._vm.metadata" (dict "ctx" $ "name" $name) | nindent 0 }}
spec:
  {{- toYaml (omit $cfg "enabled") | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}

{{/* ── VMNodeScrape (map → N) — node-level (kubelet/cadvisor) scrape ── */}}
{{- define "pleme-lib.vmNodeScrape" -}}
{{- range $name, $cfg := (.Values.vm).nodeScrapes }}
{{- if $cfg.enabled }}
---
apiVersion: {{ include "pleme-lib._vm.apiVersion" $ }}
kind: VMNodeScrape
{{- include "pleme-lib._vm.metadata" (dict "ctx" $ "name" $name) | nindent 0 }}
spec:
  {{- toYaml (omit $cfg "enabled") | nindent 2 }}
{{- end }}
{{- end }}
{{- end -}}
