{{/*
pleme-lib: compliance — namespace-scope primitives

For consumers (like the pleme-compliance chart) that own a namespace.
Application charts (microservice/worker/web) typically deploy into a
namespace owned by something else and don't render namespace-scope
resources themselves.

Maps to NIST 800-53 controls:
  CM-6  — Configuration Settings: Pod Security Standard restricted enforced
          via namespace labels (Kubernetes built-in admission)
  AC-3  — Access Enforcement: namespace-scope RBAC + ResourceQuota
  SC-5  — DoS Protection: ResourceQuota + LimitRange floors
*/}}

{{/*
Pod Security Standard labels for the namespace metadata.
At fedramp-low/moderate -> "baseline"
At fedramp-high          -> "restricted"

K8s built-in PSS admission reads pod-security.kubernetes.io/* labels and
rejects pods that violate the level. This is the cluster's last line of
defense even if a chart bypasses pleme-lib helpers.

Reference: https://kubernetes.io/docs/concepts/security/pod-security-standards/
*/}}
{{- define "pleme-lib.compliance.namespace.podSecurityLabels" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $atLeastLow := include "pleme-lib.compliance.atLeast" (list . "fedramp-low") -}}
{{- if eq $atLeastHigh "true" }}
pod-security.kubernetes.io/enforce: restricted
pod-security.kubernetes.io/enforce-version: latest
pod-security.kubernetes.io/audit: restricted
pod-security.kubernetes.io/audit-version: latest
pod-security.kubernetes.io/warn: restricted
pod-security.kubernetes.io/warn-version: latest
{{- else if eq $atLeastLow "true" }}
pod-security.kubernetes.io/enforce: baseline
pod-security.kubernetes.io/enforce-version: latest
pod-security.kubernetes.io/audit: restricted
pod-security.kubernetes.io/audit-version: latest
pod-security.kubernetes.io/warn: restricted
pod-security.kubernetes.io/warn-version: latest
{{- end }}
{{- end }}

{{/*
Namespace-scoped default-deny NetworkPolicy. Applies to all pods in the
namespace, not just the chart's own selector. Used by pleme-compliance
to give the namespace a deny-all floor.
*/}}
{{- define "pleme-lib.compliance.namespace.denyAllPolicy" -}}
{{- $required := include "pleme-lib.compliance.network.required" . -}}
{{- if eq $required "true" }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: compliance-namespace-deny-all
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.compliance.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
{{- end }}
{{- end }}

{{/*
ResourceQuota tuned to the baseline.
*/}}
{{- define "pleme-lib.compliance.namespace.resourceQuota" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $rq := ((.Values.compliance).namespace).resourceQuota | default dict -}}
{{/* Explicit string-bool comparison so users can disable via
     `enabled: "false"` without truthy-string surprise. */}}
{{- $enabled := (eq (toString $rq.enabled) "true") -}}
{{- if or (eq $atLeastMod "true") $enabled }}
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compliance-namespace-quota
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.compliance.labels" . | nindent 4 }}
spec:
  hard:
    requests.cpu: {{ $rq.requestsCpu | default "16" | quote }}
    requests.memory: {{ $rq.requestsMemory | default "24Gi" | quote }}
    limits.cpu: {{ $rq.limitsCpu | default "32" | quote }}
    limits.memory: {{ $rq.limitsMemory | default "48Gi" | quote }}
    pods: {{ $rq.pods | default "200" | quote }}
    persistentvolumeclaims: {{ $rq.pvcs | default "50" | quote }}
    services.loadbalancers: {{ $rq.loadBalancers | default "5" | quote }}
    services.nodeports: {{ $rq.nodePorts | default "0" | quote }}
{{- end }}
{{- end }}

{{/*
LimitRange. Forces every container that doesn't set requests to inherit a
sensible floor; forbids zero-request pods that would skew scheduling and
violate SC-5.
*/}}
{{- define "pleme-lib.compliance.namespace.limitRange" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $lr := ((.Values.compliance).namespace).limitRange | default dict -}}
{{- $enabled := (eq (toString $lr.enabled) "true") -}}
{{- if or (eq $atLeastMod "true") $enabled }}
apiVersion: v1
kind: LimitRange
metadata:
  name: compliance-namespace-limits
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.compliance.labels" . | nindent 4 }}
spec:
  limits:
    - type: Container
      default:
        cpu: {{ ($lr.containerDefault).cpu | default "500m" | quote }}
        memory: {{ ($lr.containerDefault).memory | default "512Mi" | quote }}
      defaultRequest:
        cpu: {{ ($lr.containerDefaultRequest).cpu | default "50m" | quote }}
        memory: {{ ($lr.containerDefaultRequest).memory | default "64Mi" | quote }}
      max:
        cpu: {{ ($lr.containerMax).cpu | default "4" | quote }}
        memory: {{ ($lr.containerMax).memory | default "4Gi" | quote }}
      min:
        cpu: {{ ($lr.containerMin).cpu | default "10m" | quote }}
        memory: {{ ($lr.containerMin).memory | default "16Mi" | quote }}
    - type: PersistentVolumeClaim
      max:
        storage: {{ ($lr.pvcMax).storage | default "500Gi" | quote }}
      min:
        storage: {{ ($lr.pvcMin).storage | default "1Gi" | quote }}
{{- end }}
{{- end }}
