{{/*
pleme-lib: compliance — FIPS 140-3 cryptographic module enforcement

Required at DoD IL5+ and FedRAMP-High in many agency overlays. Maps to:
  IA-7  — Cryptographic Module Authentication
  SC-12 — Cryptographic Key Establishment
  SC-13 — Cryptographic Protection (FIPS-validated)
  SC-17 — Public Key Infrastructure Certificates
  SC-28(1) — Cryptographic Protection at Rest

Configuration in `.Values.compliance.fips`:
  enabled: true
  module: "openssl-3.0-fips"     # CMVP cert ID or canonical module name
  cmvpCertId: "4282"             # OpenSSL 3.0 FIPS provider CMVP cert
  runtime: "go-boringcrypto"     # go-boringcrypto | openssl-3-fips |
                                  # bouncycastle-fips | aws-lc-fips |
                                  # node-fips | python-fips
  imageBaseAllowlist:            # FIPS-mode container bases
    - "registry1.dso.mil/"        # IronBank
    - "cgr.dev/chainguard/"       # Chainguard FIPS images
    - "registry.access.redhat.com/ubi"  # UBI8/9 with FIPS profile
  tls:
    minVersion: "1.3"             # 1.2 minimum, 1.3 preferred
    cipherSuites:                 # FIPS-approved only
      - "TLS_AES_256_GCM_SHA384"
      - "TLS_AES_128_GCM_SHA256"

The fips primitive injects environment variables that toggle FIPS mode
in common runtimes (Go, Java, Node, Python, OpenSSL).
*/}}

{{/*
"true" / "false" — is FIPS mode requested?
*/}}
{{- define "pleme-lib.compliance.fips.enabled" -}}
{{- $f := (.Values.compliance).fips | default dict -}}
{{- if eq (toString $f.enabled) "true" -}}true
{{- else -}}
  {{- /* pleme-lib 0.9.0+: derive from resolved overlay list */ -}}
  {{- $overlays := include "pleme-lib.overlay.list" . | fromYamlArray -}}
  {{- if has "fips" $overlays -}}true{{- else -}}false{{- end -}}
{{- end -}}
{{- end }}

{{/*
Environment variables that switch FIPS mode on in common runtimes.
Merged into the container's env list when fips.enabled=true.
*/}}
{{- define "pleme-lib.compliance.fips.env" -}}
{{- $f := (.Values.compliance).fips | default dict -}}
{{- if eq (toString $f.enabled) "true" -}}
{{- $rt := $f.runtime | default "openssl-3-fips" | toString -}}
- name: OPENSSL_FORCE_FIPS_MODE
  value: "1"
- name: OPENSSL_CONF
  value: /etc/ssl/openssl-fips.cnf
{{- if eq $rt "go-boringcrypto" }}
- name: GOEXPERIMENT
  value: boringcrypto
- name: GOFIPS
  value: "1"
- name: GODEBUG
  value: fips140=on
{{- else if eq $rt "openssl-3-fips" }}
{{- /* OpenSSL 3.0 FIPS provider — env covered above */ -}}
{{- else if eq $rt "bouncycastle-fips" }}
- name: JAVA_OPTS
  value: "-Djava.security.properties=/etc/java/fips.security"
- name: BC_FIPS
  value: "1"
{{- else if eq $rt "aws-lc-fips" }}
- name: AWSLC_FIPS_MODE
  value: "1"
{{- else if eq $rt "node-fips" }}
- name: NODE_OPTIONS
  value: "--enable-fips"
{{- else if eq $rt "python-fips" }}
- name: OPENSSL_FORCE_FIPS_MODE
  value: "1"
{{- end }}
- name: PLEMEIO_COMPLIANCE_FIPS_MODULE
  value: {{ $f.module | default "openssl-3-fips" | quote }}
{{- if $f.cmvpCertId }}
- name: PLEMEIO_COMPLIANCE_FIPS_CMVP_CERT
  value: {{ $f.cmvpCertId | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
FIPS-related annotations.
*/}}
{{- define "pleme-lib.compliance.fips.annotations" -}}
{{- $f := (.Values.compliance).fips | default dict -}}
{{- if eq (toString $f.enabled) "true" -}}
pleme.io/fips-mode: "140-3"
pleme.io/fips-runtime: {{ $f.runtime | default "openssl-3-fips" | quote }}
{{- with $f.cmvpCertId }}
pleme.io/fips-cmvp-cert-id: {{ . | quote }}
{{- end }}
{{- with $f.module }}
pleme.io/fips-module: {{ . | quote }}
{{- end }}
{{- end -}}
{{- end }}

{{/*
Manifest data — surfaces in compliance ConfigMap.
*/}}
{{- define "pleme-lib.compliance.fips.manifestData" -}}
{{- $f := (.Values.compliance).fips | default dict -}}
{{- if eq (toString $f.enabled) "true" -}}
fips-enabled: "true"
fips-module: {{ $f.module | default "openssl-3-fips" | quote }}
fips-runtime: {{ $f.runtime | default "openssl-3-fips" | quote }}
fips-cmvp-cert-id: {{ $f.cmvpCertId | default "" | quote }}
fips-tls-min-version: {{ ($f.tls).minVersion | default "1.3" | quote }}
{{- end -}}
{{- end }}

{{/*
Validate.

When fips.enabled=true:
  - runtime must be in the allowlist
  - tls.minVersion must be 1.2 or 1.3
  - if image.repository is set, it must start with one of fips.imageBaseAllowlist
  - cmvpCertId required at IL5+

When compliance.dod.impactLevel = il5 / il6:
  - fips.enabled must be true (forced from _compliance_il.tpl)
*/}}
{{- define "pleme-lib.compliance.fips.validate" -}}
{{- $f := (.Values.compliance).fips | default dict -}}
{{- $isWorkload := include "pleme-lib.compliance.isWorkload" . -}}
{{- if and (eq (toString $f.enabled) "true") (eq $isWorkload "true") -}}
  {{- $allowedRuntimes := list "go-boringcrypto" "openssl-3-fips" "bouncycastle-fips" "aws-lc-fips" "node-fips" "python-fips" -}}
  {{- $rt := $f.runtime | default "openssl-3-fips" | toString -}}
  {{- if not (has $rt $allowedRuntimes) -}}
    {{- fail (printf "compliance: compliance.fips.runtime=%q not in FIPS-validated runtime allowlist %v (SC-13, IA-7)" $rt $allowedRuntimes) -}}
  {{- end -}}
  {{- $tls := $f.tls | default dict -}}
  {{- $minV := $tls.minVersion | default "1.3" | toString -}}
  {{- if not (or (eq $minV "1.2") (eq $minV "1.3")) -}}
    {{- fail (printf "compliance: compliance.fips.tls.minVersion=%q must be 1.2 or 1.3 (SC-13)" $minV) -}}
  {{- end -}}
  {{- $allowedBases := $f.imageBaseAllowlist | default (list "registry1.dso.mil/" "cgr.dev/chainguard/" "registry.access.redhat.com/ubi") -}}
  {{- $repo := (.Values.image | default dict).repository | default "" | toString -}}
  {{- if ne $repo "" -}}
    {{- $matched := false -}}
    {{- range $allowedBases -}}
      {{- if hasPrefix . $repo -}}{{ $matched = true }}{{- end -}}
    {{- end -}}
    {{- /* For airgap consumers, the repo points at zot.<ns>.svc.cluster.local
           which can't match a public allowlist. Skip the base check when
           airgap.enabled=true — the upstream that pushed into the registry
           is what was FIPS-validated, and that's enforced via the
           supplychain layer. */ -}}
    {{- $airgap := eq (include "pleme-lib.compliance.airgap.enabled" .) "true" -}}
    {{- if and (not $matched) (not $airgap) -}}
      {{- fail (printf "compliance: fips.enabled=true requires image.repository to start with one of %v (SC-13, IronBank); got %q. For air-gap consumers set compliance.airgap.enabled=true (the upstream registry is what was FIPS-validated)." $allowedBases $repo) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}
