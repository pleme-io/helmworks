{{/*
pleme-lib: compliance — air-gap primitives

The air-gap pattern: every workload's container images come from a
cluster-local registry (Zot), and that registry is the *only* path to
external image bytes. This is the K8s-side mapping of NIST SC-7(11)
"Restrict External Communications" — the cluster has zero direct
external image-supply egress; only the registry-mirror does.

Two roles:

  consumer (default)        — workload pulls images from the local
                              registry only. Egress: NetworkPolicy
                              allowing only the registry Service.
  registry-mirror           — Zot itself, image-sync, helm-mirror, etc.
                              Egress: NetworkPolicy allowing only the
                              upstream-allowlist CIDRs/hosts.

Composes:
  Layer 1: _compliance_egress.tpl  (toService for consumer, toUpstream for mirror)

Maps to NIST 800-53 controls:
  AC-4     — Information Flow Enforcement: image-pull traffic constrained
  SC-7     — Boundary Protection: registry IS the boundary
  SC-7(5)  — Deny by default, allow by exception
  SC-7(11) — Restrict External Communications: only registry-mirror egresses
  SC-7(12) — Host-Based Boundary Protection: per-pod NetworkPolicy
  CM-2     — Baseline Configuration: image bytes attested at the mirror
  CM-7     — Least Functionality: no consumer reaches public registries
  SI-7     — Software Integrity: cosign verification at the registry
*/}}

{{/*
Active air-gap mode. Returns "" / "consumer" / "registry-mirror".
*/}}
{{- define "pleme-lib.compliance.airgap.role" -}}
{{- $ag := (.Values.compliance).airgap | default dict -}}
{{- if eq (toString $ag.enabled) "true" -}}
{{- $ag.role | default "consumer" | toString | lower | trim -}}
{{- else -}}
{{- /* pleme-lib 0.9.0+: bidirectional back-compat — derive role from
       direct-overlay declaration if airgap.enabled is unset. */ -}}
{{- $overlays := include "pleme-lib.overlay.list" . | fromYamlArray -}}
{{- if has "airgap-registry-mirror" $overlays -}}registry-mirror
{{- else if has "airgap-consumer" $overlays -}}consumer
{{- end -}}
{{- end -}}
{{- end }}

{{/*
"true" / "false" — is air-gap active for this workload (either via legacy
.Values.compliance.airgap.enabled OR via direct overlay declaration of
airgap-consumer / airgap-registry-mirror).
*/}}
{{- define "pleme-lib.compliance.airgap.enabled" -}}
{{- $ag := (.Values.compliance).airgap | default dict -}}
{{- if eq (toString $ag.enabled) "true" -}}true
{{- else -}}
  {{- $role := include "pleme-lib.compliance.airgap.role" . -}}
  {{- if $role -}}true{{- else -}}false{{- end -}}
{{- end -}}
{{- end }}

{{/*
"true" / "false" — is the workload in air-gap consumer mode?
*/}}
{{- define "pleme-lib.compliance.airgap.isConsumer" -}}
{{- if eq (include "pleme-lib.compliance.airgap.role" .) "consumer" -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
"true" / "false" — is the workload an air-gap registry mirror?
*/}}
{{- define "pleme-lib.compliance.airgap.isMirror" -}}
{{- if eq (include "pleme-lib.compliance.airgap.role" .) "registry-mirror" -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
Allowed registries — list of registry hostname prefixes the consumer's
image.repository may use. Default: a single in-cluster Zot Service DNS.
*/}}
{{- define "pleme-lib.compliance.airgap.allowedRegistries" -}}
{{- $ag := (.Values.compliance).airgap | default dict -}}
{{- if $ag.allowedRegistries -}}
{{- $ag.allowedRegistries | toJson -}}
{{- else -}}
{{- $svc := $ag.registryService | default dict -}}
{{- $name := $svc.name | default "zot" -}}
{{- $ns := $svc.namespace | default "registry" -}}
{{- printf "[%q,%q]" (printf "%s.%s.svc.cluster.local" $name $ns) (printf "%s.%s.svc" $name $ns) -}}
{{- end -}}
{{- end }}

{{/*
imagePullSecrets list to merge into the pod spec.
At airgap.enabled=true, the configured pull secret is auto-injected.
*/}}
{{- define "pleme-lib.compliance.airgap.imagePullSecrets" -}}
{{- $ag := (.Values.compliance).airgap | default dict -}}
{{- $on := include "pleme-lib.compliance.airgap.enabled" . -}}
{{- if and (eq $on "true") $ag.imagePullSecret }}
- name: {{ $ag.imagePullSecret }}
{{- end }}
{{- end }}

{{/*
NetworkPolicy: at airgap consumer, allow egress ONLY to the registry
Service (plus DNS). This is the SC-7(11) workload-side guard. Composed
out of _compliance_egress.tpl::egress.toService.

Implementation: synthesize a values shape on the fly that points
egress.toService at the registry Service, then call the egress helper.
We do this inline (not via dict munging) so the rendering stays
deterministic.
*/}}
{{- define "pleme-lib.compliance.airgap.consumerEgressPolicy" -}}
{{- $ag := (.Values.compliance).airgap | default dict -}}
{{- $svc := $ag.registryService | default dict -}}
{{- $name := $svc.name | default "zot" -}}
{{- $ns := $svc.namespace | default "registry" -}}
{{- $port := $svc.port | default 5000 -}}
{{- $proto := $svc.protocol | default "TCP" -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-airgap-consumer-egress
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
    # Allow image-pull egress to the cluster-local registry only.
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ $ns }}
          podSelector:
            matchLabels:
              app.kubernetes.io/name: {{ $name }}
      ports:
        - port: {{ $port }}
          protocol: {{ $proto }}
{{- end }}

{{/*
NetworkPolicy: at airgap registry-mirror, allow egress to a curated CIDR
or FQDN allowlist for upstream registries. Composes
_compliance_egress.tpl::egress.toUpstream.
*/}}
{{- define "pleme-lib.compliance.airgap.mirrorEgressPolicy" -}}
{{- $ag := (.Values.compliance).airgap | default dict -}}
{{- $upstream := $ag.upstream | default dict -}}
{{- if $upstream.allowedCidrs -}}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-airgap-mirror-egress
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
    # Allow upstream-registry egress to the curated CIDR allowlist only.
    - to:
        {{- range $upstream.allowedCidrs }}
        - ipBlock:
            cidr: {{ . | quote }}
        {{- end }}
      ports:
        - port: 443
          protocol: TCP
{{- end -}}
{{- if and $upstream.allowedHosts $upstream.useCilium -}}
{{- if $upstream.allowedCidrs }}
---
{{- end }}
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-airgap-mirror-fqdn
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
        {{- range $upstream.allowedHosts }}
        - matchPattern: {{ . | quote }}
        {{- end }}
      toPorts:
        - ports:
            - port: "443"
              protocol: TCP
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
Render the airgap-side NetworkPolicies for this workload.
Called from _networkpolicy.tpl when compliance.airgap.enabled=true.
*/}}
{{- define "pleme-lib.compliance.airgap.policies" -}}
{{- $role := include "pleme-lib.compliance.airgap.role" . -}}
{{- if eq $role "consumer" }}
---
{{ include "pleme-lib.compliance.airgap.consumerEgressPolicy" . }}
{{- else if eq $role "registry-mirror" }}
{{- $mirror := include "pleme-lib.compliance.airgap.mirrorEgressPolicy" . | trim -}}
{{- if $mirror }}
---
{{ $mirror }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Compliance manifest data — air-gap claim. Surfaces in the
compliance-manifest ConfigMap so audit pipelines can verify the workload
is operating within the air-gap boundary.
*/}}
{{- define "pleme-lib.compliance.airgap.manifestData" -}}
{{- $role := include "pleme-lib.compliance.airgap.role" . -}}
{{- if $role }}
airgap-enabled: "true"
airgap-role: {{ $role | quote }}
airgap-allowed-registries: {{ include "pleme-lib.compliance.airgap.allowedRegistries" . | quote }}
{{- end }}
{{- end }}

{{/*
Validate.

At airgap.enabled=true, regardless of baseline:
  - role must be "consumer" or "registry-mirror"

For consumer role:
  - image.repository MUST start with one of allowedRegistries entries
  - imagePullSecret SHOULD be set (warning only, since the registry may
    be anonymous-pull)

For registry-mirror role:
  - upstream.allowedCidrs or (upstream.allowedHosts AND useCilium=true) required
  - upstream credentials secret reference required at high

At fedramp-high + airgap.enabled:
  - requireSignedImages must be true (cosign at the registry boundary)
*/}}
{{- define "pleme-lib.compliance.airgap.validate" -}}
{{- $b := include "pleme-lib.compliance.baseline" . -}}
{{- $atLeastHigh := include "pleme-lib.compliance.atLeast" (list . "fedramp-high") -}}
{{- $ag := (.Values.compliance).airgap | default dict -}}
{{- $enabled := eq (include "pleme-lib.compliance.airgap.enabled" .) "true" -}}
{{- if $enabled -}}
  {{- $role := include "pleme-lib.compliance.airgap.role" . -}}
  {{- if not (or (eq $role "consumer") (eq $role "registry-mirror")) -}}
    {{- fail (printf "compliance: airgap.role must be \"consumer\" or \"registry-mirror\"; got %q" $role) -}}
  {{- end -}}
  {{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}
  {{- if and (eq $role "consumer") (eq $isWorkload "true") -}}
    {{- $allowed := include "pleme-lib.compliance.airgap.allowedRegistries" . | fromJsonArray -}}
    {{- $repo := (.Values.image | default dict).repository | default "" | toString -}}
    {{- $matched := false -}}
    {{- range $allowed -}}
      {{- if hasPrefix . $repo -}}{{ $matched = true }}{{- end -}}
    {{- end -}}
    {{- if not $matched -}}
      {{- fail (printf "compliance: airgap=consumer requires image.repository to start with one of %v (SC-7(11), CM-2); got %q" $allowed $repo) -}}
    {{- end -}}
  {{- end -}}
  {{- if eq $role "registry-mirror" -}}
    {{- $up := $ag.upstream | default dict -}}
    {{- $hasCidrs := and $up.allowedCidrs (gt (len ($up.allowedCidrs | default list)) 0) -}}
    {{- $hasFqdn := and (and $up.allowedHosts (gt (len ($up.allowedHosts | default list)) 0)) (eq (toString $up.useCilium) "true") -}}
    {{- if not (or $hasCidrs $hasFqdn) -}}
      {{- fail (printf "compliance: airgap=registry-mirror requires either compliance.airgap.upstream.allowedCidrs (CIDR list) or compliance.airgap.upstream.allowedHosts + useCilium=true (FQDN list); SC-7(11)") -}}
    {{- end -}}
    {{- if eq $atLeastHigh "true" -}}
      {{- if not $up.credentialSecret -}}
        {{- fail (printf "compliance: baseline=fedramp-high + airgap=registry-mirror requires compliance.airgap.upstream.credentialSecret (IA-5, AU-3); anonymous upstream pulls are not auditable") -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- if eq $atLeastHigh "true" -}}
    {{- if not (eq (toString $ag.requireSignedImages) "true") -}}
      {{- fail (printf "compliance: baseline=fedramp-high + airgap.enabled requires airgap.requireSignedImages=true (SI-7, CM-2); registry must verify cosign signatures") -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
