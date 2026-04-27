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
RBAC, use ClusterRole/ClusterRoleBinding directly (or compose an analogous helper).
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
