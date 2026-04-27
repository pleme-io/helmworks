{{/*
pleme-lib: compliance — egress shape primitives

Foundation primitive: every "this workload is allowed to talk only to X"
pattern composes against this. Air-gap is the canonical first consumer
(workload → local registry only). Future consumers (workload → database
only, workload → auth only, workload → upstream allowlist only) reuse
the same shapes.

Maps to NIST 800-53 controls:
  AC-4     — Information Flow Enforcement
  SC-7     — Boundary Protection
  SC-7(5)  — Deny by default, allow by exception
  SC-7(11) — Restrict External Communications: workload egress only to
             explicitly named services or upstream hosts
  SC-7(12) — Host-Based Boundary Protection: per-pod NetworkPolicy

Two shapes:

  egress.toService { name, namespace, ports }
    Workload egresses ONLY to a specific Kubernetes Service. The
    canonical "I talk only to the local registry / database / auth"
    pattern. Implemented as a NetworkPolicy with a podSelector for the
    upstream Service and a port allowlist.

  egress.toUpstream { allowedHosts, ports }
    Workload egresses ONLY to specific external hosts (resolved by DNS
    at runtime by the CNI). The canonical "registry-mirror talks to a
    curated set of upstream registries" pattern. Implemented as a
    NetworkPolicy with no podSelector (matches all pods) and a CIDR
    block resolved from the host list.
*/}}

{{/*
Emit a NetworkPolicy that allows this chart's workload to egress ONLY
to a specific Service in the cluster.

Required fields under .Values.compliance.egress.toService:
  name        — Service name
  namespace   — Service namespace (defaults to this chart's namespace)
  ports       — list of { port, protocol } the workload may reach
                (defaults to [{ port: 443, protocol: TCP }])
*/}}
{{- define "pleme-lib.compliance.egress.toService" -}}
{{- $svc := ((.Values.compliance).egress).toService | default dict -}}
{{- if $svc.name -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-egress-svc-{{ $svc.name }}
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ $svc.namespace | default (include "pleme-lib.namespace" .) }}
          podSelector:
            matchLabels:
              app.kubernetes.io/name: {{ $svc.name }}
      ports:
        {{- $ports := $svc.ports | default (list (dict "port" 443 "protocol" "TCP")) }}
        {{- toYaml $ports | nindent 8 }}
{{- end }}
{{- end }}

{{/*
Emit a NetworkPolicy that allows this chart's workload to egress ONLY
to a specific allowlist of external hosts (CIDRs).

This is the "registry-mirror" / "upstream allowlist" shape. CIDR-based
because Kubernetes NetworkPolicy doesn't natively support DNS hostnames
in egress rules — operators are expected to resolve hosts to CIDRs at
deploy time, or use a CNI extension (Cilium FQDN policy) on top.

Required fields under .Values.compliance.egress.toUpstream:
  allowedCidrs — list of "x.y.z.w/N" CIDRs
  ports        — list of { port, protocol }
*/}}
{{- define "pleme-lib.compliance.egress.toUpstream" -}}
{{- $up := ((.Values.compliance).egress).toUpstream | default dict -}}
{{- if $up.allowedCidrs -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-egress-upstream
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Egress
  egress:
    - to:
        {{- range $up.allowedCidrs }}
        - ipBlock:
            cidr: {{ . | quote }}
        {{- end }}
      ports:
        {{- $ports := $up.ports | default (list (dict "port" 443 "protocol" "TCP")) }}
        {{- toYaml $ports | nindent 8 }}
{{- end }}
{{- end }}

{{/*
Cilium FQDN-based egress policy (preferred over CIDR when the CNI
supports it). Matches by DNS name rather than IP. This is the canonical
"upstream-allowlist" shape on Cilium-equipped clusters.

NOTE: This emits a CiliumNetworkPolicy CRD. The cluster must have Cilium
with the L7 / DNS proxy enabled. On non-Cilium clusters, fall back to
egress.toUpstream (CIDR-based).
*/}}
{{- define "pleme-lib.compliance.egress.toUpstreamFqdn" -}}
{{- $up := ((.Values.compliance).egress).toUpstream | default dict -}}
{{- if and $up.allowedHosts $up.useCilium -}}
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-egress-upstream-fqdn
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    {{- include "pleme-lib.compliance.annotations" . | nindent 4 }}
spec:
  endpointSelector:
    matchLabels:
      {{- include "pleme-lib.selectorLabels" . | nindent 6 }}
  egress:
    - toFQDNs:
        {{- range $up.allowedHosts }}
        - matchName: {{ . | quote }}
        {{- end }}
      toPorts:
        - ports:
            {{- $ports := $up.ports | default (list (dict "port" "443" "protocol" "TCP")) }}
            {{- toYaml $ports | nindent 12 }}
    # Allow egress to the Cilium DNS proxy itself (kube-system kube-dns)
    - toEndpoints:
        - matchLabels:
            "k8s:io.kubernetes.pod.namespace": kube-system
            "k8s:k8s-app": kube-dns
      toPorts:
        - ports:
            - port: "53"
              protocol: ANY
          rules:
            dns:
              - matchPattern: "*"
{{- end }}
{{- end }}

{{/*
Validate egress configuration.

At fedramp-moderate+, when compliance.egress is configured, exactly one
of toService.name or toUpstream.allowedCidrs must be set — they are
mutually exclusive shapes.

At fedramp-high, when compliance.egress.toUpstream is set, the
allowedCidrs list must be non-empty (no implicit "all of internet").
*/}}
{{- define "pleme-lib.compliance.egress.validate" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $eg := (.Values.compliance).egress | default dict -}}
{{- $svc := $eg.toService | default dict -}}
{{- $up := $eg.toUpstream | default dict -}}
{{- if eq $atLeastMod "true" -}}
  {{- if and $svc.name $up.allowedCidrs -}}
    {{- fail (printf "compliance: egress.toService and egress.toUpstream are mutually exclusive (AC-4); pick one shape per workload") -}}
  {{- end -}}
{{- end -}}
{{- if eq $atLeastHigh "true" -}}
  {{- if and $up $up.allowedHosts (not $up.allowedCidrs) (not $up.useCilium) -}}
    {{- fail (printf "compliance: baseline=fedramp-high requires egress.toUpstream.allowedCidrs to be non-empty when allowedHosts is set, OR egress.toUpstream.useCilium=true (SC-7(11))") -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Render the full set of egress NetworkPolicies for this workload.
Called from _networkpolicy.tpl when compliance.egress is configured.
*/}}
{{- define "pleme-lib.compliance.egress.policies" -}}
{{- $eg := (.Values.compliance).egress | default dict -}}
{{- $svc := $eg.toService | default dict -}}
{{- $up := $eg.toUpstream | default dict -}}
{{- if $svc.name -}}
---
{{ include "pleme-lib.compliance.egress.toService" . }}
{{- end }}
{{- if $up.allowedCidrs -}}
---
{{ include "pleme-lib.compliance.egress.toUpstream" . }}
{{- end }}
{{- if and $up.allowedHosts $up.useCilium -}}
---
{{ include "pleme-lib.compliance.egress.toUpstreamFqdn" . }}
{{- end }}
{{- end }}
