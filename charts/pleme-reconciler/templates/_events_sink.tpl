{{/*
pleme-reconciler.k8sEventsSink

Renders ServiceAccount + Role + RoleBinding so the consumer's pod
can write Events into its namespace. Used by magma-stream's
K8sEventSink adapter to surface reconcile events as K8s Events
(viewable via `kubectl get events --field-selector
reason=MagmaPlanComputed`).

Skipped entirely when `reconciler.k8sEventsSink.enabled: false`.

The consumer's pod template must mount this ServiceAccount
(via `pleme-lib.deployment`'s `serviceAccountName` value).
*/}}
{{- define "pleme-reconciler.k8sEventsSink" -}}
{{- $sink := .Values.reconciler.k8sEventsSink | default dict -}}
{{- if $sink.enabled }}
{{- $kind := .Values.reconciler.kind | default (printf "%s" .Chart.Name) -}}
{{- $name := $sink.name | default (printf "%s-events-writer" $kind) -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ $name }}
  labels:
    app.kubernetes.io/name:       {{ .Chart.Name | quote }}
    app.kubernetes.io/component:  events-writer
    app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
    magma.pleme.io/reconciler:    {{ $kind | quote }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ $name }}
  labels:
    magma.pleme.io/reconciler: {{ $kind | quote }}
rules:
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["create", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $name }}
  labels:
    magma.pleme.io/reconciler: {{ $kind | quote }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ $name }}
subjects:
  - kind: ServiceAccount
    name: {{ $name }}
    namespace: {{ .Release.Namespace }}
{{- end }}
{{- end }}
