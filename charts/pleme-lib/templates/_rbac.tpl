{{/*
pleme-lib: namespace-scoped RBAC primitives — Role + RoleBinding

Renders one or more namespace-scoped Role + RoleBinding pairs from a values map,
each binding to one or more subjects (typically a ServiceAccount in the same
namespace). Consumers structure values as:

  rbac:
    roles:
      <name>:                 # rendered as Role/<name> + RoleBinding/<name>
        rules:
          - apiGroups: [""]
            resources: ["pods", "namespaces"]
            verbs: ["get", "list", "watch"]
        subjects:
          - kind: ServiceAccount
            name: my-sa
            # namespace defaults to release namespace when omitted
        # roleRef defaults to the rendered Role/<name>; override only for cross-binding patterns

Use this when a chart's primary SA needs in-namespace verbs. For cluster-scoped
RBAC use `pleme-lib.clusterRBAC` (below).

  rbac:
    clusterRoles:
      <name>:                      # ClusterRole/<name> (+ ClusterRoleBinding unless binding: false)
        rules: [ ... ]
        # aggregateLabels:         # merged onto the ClusterRole's labels so an aggregated
        #   rbac.crossplane.io/aggregate-to-crossplane: "true"   # role (e.g. crossplane's) absorbs these rules
        # aggregationRule: { ... } # for a ClusterRole that is itself an aggregator
        # binding: false           # aggregation-only ClusterRole: emit no ClusterRoleBinding
        subjects:
          - { kind: ServiceAccount, name: my-sa }                # namespace defaults to release ns
          - { kind: Group, name: "system:masters" }              # Group/User get apiGroup, no namespace
*/}}

{{- define "pleme-lib.namespacedRBAC" -}}
{{- range $name, $spec := (.Values.rbac).roles }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ $name | kebabcase }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  {{- with (include "pleme-lib.attestationAnnotations" $) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
rules:
  {{- toYaml $spec.rules | nindent 2 }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ $name | kebabcase }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ default ($name | kebabcase) (($spec.roleRef).name) }}
subjects:
  {{- range $spec.subjects }}
  - kind: {{ default "ServiceAccount" .kind }}
    name: {{ .name }}
    namespace: {{ default (include "pleme-lib.namespace" $) .namespace }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
pleme-lib.clusterRBAC — cluster-scoped ClusterRole (+ ClusterRoleBinding) pairs from a
.Values.rbac.clusterRoles map. Mirror of namespacedRBAC. Fleet-generic: any Composition
whose core-controller does SSA against a vendor MR group needs an aggregate-to-crossplane
ClusterRole; `aggregateLabels` is the typed slot for that. `binding: false` emits the
ClusterRole only (aggregation-only). ServiceAccount subjects get a namespace; Group/User
subjects get an apiGroup.
*/}}
{{- define "pleme-lib.clusterRBAC" -}}
{{- range $name, $spec := (.Values.rbac).clusterRoles }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ $name | kebabcase }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
    {{- with $spec.aggregateLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  {{- with (include "pleme-lib.attestationAnnotations" $) }}
  annotations:
    {{- . | nindent 4 }}
  {{- end }}
{{- with $spec.aggregationRule }}
aggregationRule:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with $spec.rules }}
rules:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- if or (not (hasKey $spec "binding")) $spec.binding }}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ $name | kebabcase }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ default ($name | kebabcase) (($spec.roleRef).name) }}
subjects:
  {{- range $spec.subjects }}
  - kind: {{ default "ServiceAccount" .kind }}
    name: {{ .name }}
    {{- if eq (default "ServiceAccount" .kind) "ServiceAccount" }}
    namespace: {{ default (include "pleme-lib.namespace" $) .namespace }}
    {{- else }}
    apiGroup: {{ .apiGroup | default "rbac.authorization.k8s.io" }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}
