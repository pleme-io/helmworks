{{/*
pleme-lib: compliance — network primitives

Maps to NIST 800-53 controls:
  AC-4  — Information Flow Enforcement: default-deny NetworkPolicy
  SC-7  — Boundary Protection: NetworkPolicy + Ingress TLS
  SC-7(4) — External Telecommunications Services: NAT egress only (cluster-level)
  SC-7(5) — Deny by default, allow by exception
  SC-8  — Transmission Confidentiality: TLS-only egress on 443
  SC-13 — Cryptographic Protection: TLS 1.2+

At moderate+, every workload renders a default-deny NetworkPolicy. Allow rules
are explicit and additive via .Values.networkPolicy.additionalIngress/Egress
or via .Values.compliance.network.allowEgress / allowIngress (typed shortcuts).
*/}}

{{/*
Whether NetworkPolicy is mandatory at the current baseline.
*/}}
{{- define "pleme-lib.compliance.network.required" -}}
{{- $atLeastMod := include "pleme-lib.compliance.atLeast" (list . "fedramp-moderate") -}}
{{- if eq $atLeastMod "true" -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
Default-deny NetworkPolicy. Always emitted when network.required = true.
This is the floor: no traffic in or out unless an explicit allow says so.
*/}}
{{- define "pleme-lib.compliance.network.denyAll" -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-compliance-deny-all
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
    - Ingress
    - Egress
{{- end }}

{{/*
DNS egress allow. Required at moderate+ because every workload needs cluster
DNS resolution and a default-deny would otherwise break service discovery.
*/}}
{{- define "pleme-lib.compliance.network.allowDns" -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-compliance-allow-dns
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
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
{{- end }}

{{/*
TLS-only egress allow. Allows outbound on 443/TCP only, satisfying SC-8/SC-13.
Workloads that need plaintext egress (e.g., Redis, Postgres in-cluster) must
add explicit additionalEgress rules; in-cluster traffic is generally acceptable
without TLS because it stays inside the trust boundary. This rule is the
cluster-edge guard.
*/}}
{{- define "pleme-lib.compliance.network.allowTlsEgress" -}}
{{- $cn := (.Values.compliance).network | default dict -}}
{{/* `false | default true` returns true in Sprig, so an explicit
     toString check is required for users who want to disable. */}}
{{- $allow := true -}}
{{- if hasKey $cn "allowTlsEgress" -}}{{- $allow = (eq (toString $cn.allowTlsEgress) "true") -}}{{- end -}}
{{- if $allow }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-compliance-allow-tls-egress
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
    - ports:
        - port: 443
          protocol: TCP
{{- end }}
{{- end }}

{{/*
Render the full set of compliance NetworkPolicies.
Called from _networkpolicy.tpl when baseline >= moderate.
*/}}
{{- define "pleme-lib.compliance.network.policies" -}}
{{- $required := include "pleme-lib.compliance.network.required" . -}}
{{- if eq $required "true" }}
---
{{ include "pleme-lib.compliance.network.denyAll" . }}
---
{{ include "pleme-lib.compliance.network.allowDns" . }}
{{- $tlsBlock := include "pleme-lib.compliance.network.allowTlsEgress" . | trim -}}
{{- if $tlsBlock }}
---
{{ $tlsBlock }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate.
*/}}
{{- define "pleme-lib.compliance.network.validate" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $required := include "pleme-lib.compliance.network.required" . -}}
{{- if eq $required "true" -}}
  {{- $np := .Values.networkPolicy | default dict -}}
  {{- if hasKey $np "enabled" -}}
    {{- if eq (toString $np.enabled) "false" -}}
      {{- fail (printf "compliance: baseline=%s requires NetworkPolicy enforcement; networkPolicy.enabled=false is forbidden (AC-4, SC-7)" $b) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
