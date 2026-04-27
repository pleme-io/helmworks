{{/*
pleme-lib: compliance — RBAC / authorization primitives

Foundation primitive: every chart that needs Kubernetes RBAC composes
against these. Eliminates the most common compliance findings — wildcard
verbs, wildcard resources, wildcard apiGroups, cluster-admin bindings —
by making them template-time `fail()` errors.

Maps to NIST 800-53 controls:
  AC-3  — Access Enforcement: typed Role / RoleBinding shapes
  AC-6  — Least Privilege: explicit refusal of `verbs: ["*"]`
  AC-6(1) — Authorize Access to Security Functions: wildcard apiGroups
            forbidden at high
  AC-6(7) — Review of User Privileges: rolebinding subjects must be
            explicit ServiceAccounts, not Group:system:authenticated
  CM-7  — Least Functionality

Three shapes — Role (namespace-scoped), ClusterRole (cluster-scoped,
discouraged), and bindings. The defaults are restrictive: a chart that
declares an empty `compliance.authz.role.rules` gets a Role with zero
permissions, not "all permissions".
*/}}

{{/*
Emit a namespace-scoped Role for this workload.

Required fields under .Values.compliance.authz.role:
  rules — list of rule objects { apiGroups, resources, verbs, resourceNames? }

Defaults to NO permissions (an empty Role is fine — the workload still
authenticates as a SA, just can't do anything via the K8s API). This is
the right default for the 95% of workloads that just talk to other pods,
not to the K8s API.
*/}}
{{- define "pleme-lib.compliance.authz.role" -}}
{{- $r := ((.Values.compliance).authz).role | default dict -}}
{{- if $r.rules -}}
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
rules:
  {{- toYaml $r.rules | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Emit a RoleBinding pointing at this chart's ServiceAccount.

Defaults to binding the chart's SA to the chart's Role (same name, same
namespace). Override .Values.compliance.authz.roleBinding.subjects to
bind additional principals — the validator below rejects bindings to
Group:system:authenticated and User:* without explicit opt-in.
*/}}
{{- define "pleme-lib.compliance.authz.roleBinding" -}}
{{- $rb := ((.Values.compliance).authz).roleBinding | default dict -}}
{{- $r := ((.Values.compliance).authz).role | default dict -}}
{{- if $r.rules -}}
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "pleme-lib.fullname" . }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ include "pleme-lib.fullname" . }}
subjects:
  {{- if $rb.subjects }}
  {{- toYaml $rb.subjects | nindent 2 }}
  {{- else }}
  - kind: ServiceAccount
    name: {{ include "pleme-lib.serviceAccountName" . }}
    namespace: {{ include "pleme-lib.namespace" . }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Emit a ClusterRole. Discouraged unless genuinely cluster-scope.

Required fields under .Values.compliance.authz.clusterRole:
  rules — list of rule objects (same shape as Role)

The validator below rejects cluster-admin-equivalent shapes
(verbs: ["*"], resources: ["*"], apiGroups: ["*"]) at moderate+.
*/}}
{{- define "pleme-lib.compliance.authz.clusterRole" -}}
{{- $cr := ((.Values.compliance).authz).clusterRole | default dict -}}
{{- if $cr.rules -}}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: {{ include "pleme-lib.fullname" . }}-{{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
rules:
  {{- toYaml $cr.rules | nindent 2 }}
{{- end }}
{{- end }}

{{/*
Emit a ClusterRoleBinding pointing at this chart's ServiceAccount.
*/}}
{{- define "pleme-lib.compliance.authz.clusterRoleBinding" -}}
{{- $crb := ((.Values.compliance).authz).clusterRoleBinding | default dict -}}
{{- $cr := ((.Values.compliance).authz).clusterRole | default dict -}}
{{- if $cr.rules -}}
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: {{ include "pleme-lib.fullname" . }}-{{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: {{ include "pleme-lib.fullname" . }}-{{ include "pleme-lib.namespace" . }}
subjects:
  {{- if $crb.subjects }}
  {{- toYaml $crb.subjects | nindent 2 }}
  {{- else }}
  - kind: ServiceAccount
    name: {{ include "pleme-lib.serviceAccountName" . }}
    namespace: {{ include "pleme-lib.namespace" . }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
Validate authz rules.

At fedramp-moderate+:
  - Role rules cannot have verbs: ["*"]
  - Role rules cannot have resources: ["*"]
  - ClusterRole rules cannot have verbs: ["*"] without explicit opt-in
  - RoleBinding subjects cannot be Group:system:authenticated /
    Group:system:unauthenticated / User:* (unless explicit allowList)

At fedramp-high:
  - ClusterRole rules cannot have apiGroups: ["*"]
  - No binding to ClusterRole "cluster-admin"
*/}}
{{- define "pleme-lib.compliance.authz.validate" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $authz := (.Values.compliance).authz | default dict -}}
{{- $allow := $authz.allowList | default dict -}}
{{- if eq $atLeastMod "true" -}}
  {{- $r := $authz.role | default dict -}}
  {{- range $idx, $rule := ($r.rules | default list) -}}
    {{- if has "*" ($rule.verbs | default list) -}}
      {{- fail (printf "compliance: baseline=%s forbids Role verbs: [\"*\"] (AC-6); rule index %d. Enumerate verbs explicitly." $b $idx) -}}
    {{- end -}}
    {{- if has "*" ($rule.resources | default list) -}}
      {{- fail (printf "compliance: baseline=%s forbids Role resources: [\"*\"] (AC-6); rule index %d. Enumerate resources explicitly." $b $idx) -}}
    {{- end -}}
  {{- end -}}
  {{- $cr := $authz.clusterRole | default dict -}}
  {{- range $idx, $rule := ($cr.rules | default list) -}}
    {{- if has "*" ($rule.verbs | default list) -}}
      {{- if not $allow.clusterWildcardVerbs -}}
        {{- fail (printf "compliance: baseline=%s forbids ClusterRole verbs: [\"*\"] without compliance.authz.allowList.clusterWildcardVerbs=true (AC-6); rule index %d" $b $idx) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{/* RoleBinding / ClusterRoleBinding subject checks */}}
  {{- $forbidGroups := list "system:authenticated" "system:unauthenticated" "system:masters" -}}
  {{- $allowedGroups := $allow.bindingGroups | default list -}}
  {{- $rb := $authz.roleBinding | default dict -}}
  {{- range $idx, $sub := ($rb.subjects | default list) -}}
    {{- if eq ($sub.kind | default "") "Group" -}}
      {{- if and (has $sub.name $forbidGroups) (not (has $sub.name $allowedGroups)) -}}
        {{- fail (printf "compliance: baseline=%s forbids RoleBinding subject Group:%s (AC-6, AC-6(7)); subject index %d" $b $sub.name $idx) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- if eq $atLeastHigh "true" -}}
  {{- $cr := $authz.clusterRole | default dict -}}
  {{- range $idx, $rule := ($cr.rules | default list) -}}
    {{- if has "*" ($rule.apiGroups | default list) -}}
      {{- if not $allow.clusterWildcardApiGroups -}}
        {{- fail (printf "compliance: baseline=fedramp-high forbids ClusterRole apiGroups: [\"*\"] without compliance.authz.allowList.clusterWildcardApiGroups=true (AC-6(1)); rule index %d" $idx) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- $crb := $authz.clusterRoleBinding | default dict -}}
  {{- if eq (($crb.roleRef | default dict).name | toString) "cluster-admin" -}}
    {{- fail (printf "compliance: baseline=fedramp-high forbids ClusterRoleBinding -> cluster-admin (AC-6, CM-7); use a least-privilege ClusterRole") -}}
  {{- end -}}
{{- end -}}
{{- end }}
