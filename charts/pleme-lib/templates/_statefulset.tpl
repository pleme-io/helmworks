{{/*
pleme-lib: statefulset named template

Produces a standard StatefulSet for pleme-io STATEFUL workloads (metric/log
stores, brokers, databases) — the structural peer of `pleme-lib.deployment`.
Before this primitive, every stateful workload (VictoriaMetrics, NATS, CNPG)
had to hand-roll its own pod spec and thereby BYPASSED pleme-lib's compliance
baseline + attestation. This template closes that gap: the SAME compliance
validators, security baseline, attestation annotations, audit annotations,
overlay-driven podEnv, and observability that `pleme-lib.deployment` enforces
now apply to stateful workloads by construction.

Stateful additions over the Deployment surface:
  * `spec.serviceName`         — the governing headless Service (defaults to
                                 `<fullname>-headless`); set `.Values.statefulset.serviceName`.
  * `spec.volumeClaimTemplates`— per-replica persistent storage; from
                                 `.Values.volumeClaimTemplates` (a list of PVC
                                 specs). EMPTY ⇒ no claim templates (an ephemeral
                                 StatefulSet, still ordered + stable-identity).
  * `spec.podManagementPolicy` — `.Values.statefulset.podManagementPolicy`
                                 (default OrderedReady).
  * `spec.updateStrategy`      — `.Values.updateStrategy` (default RollingUpdate).

NOTE (tracked follow-up): the pod template below mirrors
`pleme-lib.deployment`'s. The DRY destination is a shared `pleme-lib.podSpec`
partial consumed by both — deferred to a focused change because the extraction
touches ~10 existing Deployment consumers and needs a helm-template byte-diff
to prove no drift. Until then, edits to the pod contract MUST be applied to
BOTH _deployment.tpl and _statefulset.tpl.
*/}}

{{- define "pleme-lib.statefulset" -}}
{{- include "pleme-lib.compliance.validate" . -}}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  {{- $resAnnotations := include "pleme-lib.resourceAnnotations" . }}
  {{- if $resAnnotations }}
  annotations:
    {{- $resAnnotations | nindent 4 }}
  {{- end }}
spec:
  serviceName: {{ (.Values.statefulset).serviceName | default (printf "%s-headless" (include "pleme-lib.fullname" .)) }}
  {{- if not (.Values.autoscaling).enabled }}
  replicas: {{ .Values.replicaCount | default 1 }}
  {{- end }}
  podManagementPolicy: {{ (.Values.statefulset).podManagementPolicy | default "OrderedReady" }}
  selector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  {{- with .Values.updateStrategy }}
  updateStrategy:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  template:
    metadata:
      labels:
        {{- include "pleme-lib.selectorLabels" . | nindent 8 }}
        app: {{ include "pleme-lib.fullname" . }}
        {{- $cl := include "pleme-lib.compliance.labels" . | trim }}
        {{- if $cl }}
        {{- $cl | nindent 8 }}
        {{- end }}
      annotations:
        {{- include "pleme-lib.prometheusAnnotations" . | nindent 8 }}
        {{- include "pleme-lib.istioAnnotations" . | nindent 8 }}
        {{- include "pleme-lib.compliance.annotations" . | nindent 8 }}
        {{- include "pleme-lib.compliance.audit.annotations" . | nindent 8 }}
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
    spec:
      serviceAccountName: {{ include "pleme-lib.serviceAccountName" . }}
      automountServiceAccountToken: {{ include "pleme-lib.compliance.automountServiceAccountToken" . }}
      {{- $airgapSecrets := include "pleme-lib.compliance.airgap.imagePullSecrets" . | trim }}
      {{- if or .Values.imagePullSecrets $airgapSecrets }}
      imagePullSecrets:
        {{- with .Values.imagePullSecrets }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- if $airgapSecrets }}
        {{- $airgapSecrets | nindent 8 }}
        {{- end }}
      {{- end }}
      securityContext:
        {{- include "pleme-lib.podSecurityContext" . | nindent 8 }}
      {{- if or (.Values.shinkaWait).enabled (gt (len (.Values.initContainers | default list)) 0) }}
      initContainers:
        {{- include "pleme-lib.shinkaWaitInitContainer" . | nindent 8 }}
        {{- with .Values.initContainers }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- end }}
      containers:
        - name: {{ include "pleme-lib.name" . }}
          image: {{ include "pleme-lib.compliance.image" . }}
          imagePullPolicy: {{ include "pleme-lib.compliance.image.pullPolicy" . }}
          {{- with .Values.command }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.args }}
          args:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.ports }}
          ports:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- $overlayEnv := include "pleme-lib.overlay.dispatchAll" (list "podEnv" .) | trim }}
          {{- if or (or (.Values.downwardApi).enabled (gt (len (.Values.env | default list)) 0)) $overlayEnv }}
          env:
            {{- if (.Values.downwardApi).enabled }}
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
            - name: POD_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: NODE_NAME
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            {{- end }}
            {{- if $overlayEnv }}
            {{- $overlayEnv | nindent 12 }}
            {{- end }}
            {{- with .Values.env }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- end }}
          {{- with .Values.envFrom }}
          envFrom:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          securityContext:
            {{- include "pleme-lib.containerSecurityContext" . | nindent 12 }}
          livenessProbe:
            {{- include "pleme-lib.livenessProbe" . | nindent 12 }}
          readinessProbe:
            {{- include "pleme-lib.readinessProbe" . | nindent 12 }}
          {{- if (.Values.startupProbe).enabled }}
          startupProbe:
            {{- include "pleme-lib.startupProbe" . | nindent 12 }}
          {{- end }}
          {{- with .Values.volumeMounts }}
          volumeMounts:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.lifecycle }}
          lifecycle:
            {{- toYaml . | nindent 12 }}
          {{- end }}
        {{- range .Values.sidecars }}
        - {{- toYaml . | nindent 10 }}
        {{- end }}
      {{- with .Values.volumes }}
      volumes:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      terminationGracePeriodSeconds: {{ .Values.terminationGracePeriodSeconds | default 30 }}
      {{- with .Values.priorityClassName }}
      priorityClassName: {{ . }}
      {{- end }}
      {{- $availReq := include "pleme-lib.compliance.availability.required" . }}
      {{- if or .Values.topologySpreadConstraints (eq $availReq "true") }}
      topologySpreadConstraints:
      {{- if eq $availReq "true" }}
      {{- include "pleme-lib.compliance.availability.topologySpread" . | nindent 8 }}
      {{- else }}
        {{- toYaml .Values.topologySpreadConstraints | nindent 8 }}
      {{- end }}
      {{- end }}
      {{- $sched := .Values.global | default dict }}
      {{- with (.Values.nodeSelector | default $sched.nodeSelector) }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with (.Values.tolerations | default $sched.tolerations) }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  {{- with .Values.volumeClaimTemplates }}
  volumeClaimTemplates:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
