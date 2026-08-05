{{/*
pleme-lib: trust — private-CA trust anchor, applied as a quality

Maps to NIST 800-53 controls:
  SC-8  — Transmission Confidentiality: in-cluster traffic is TLS, and the
          client can actually VERIFY it (a served cert nobody trusts is not
          SC-8, it is an unverified channel with extra steps)
  SC-12 — Cryptographic Key Management: the CA is SEEDED from the secret
          store, never minted per-install
  SC-17 — PKI Certificates: leaves are issued from ONE domain issuer, so a
          renewal chains to the same anchor consumers already trust

WHAT THIS REMOVES, and it is a real defect class rather than a tidy-up.

A private CA ends up pinned in several unrelated places -- a repo file a
pipeline installs into a runner, node userData, a chart's values, the live
Secret -- and nothing knows they must agree. They drift. The drift is invisible
because every copy carries the SAME SUBJECT, so checking by eye reads
`CN=<cluster> CA` in both places and reports a match; only the public key
differs. Measured on camelot 2026-08-05: runner trust pinned CF:0F:CA:59 while
the cluster served 1C:36:BE:00, both `CN=camelot-eks cluster CA`, surfacing as
`error sending request for url (https://...)` -- which reads as a network fault.

Two causes, and the second is why it recurs:
  1. pins drift, because nothing compares them
  2. the CA was MINTED by a cert-manager SelfSigned issuer, so every cluster
     inception produced a new key and invalidated every pin at once

This template owns the chart-side half: a consuming chart declares the quality
and gets its cert from the domain issuer plus the anchor propagated to its
process, instead of hand-rolling both. The cross-surface fingerprint check is
NOT expressible in Go templates (there is no digest function), so it lives in
the `trust` tool; see `pleme-lib.trust.anchorAnnotations` for the handoff.

WHY THE LIBRARY ISSUES THE CERT rather than only mounting the bundle: zot's
original hand-applied cert had NO basicConstraints, so `CA:TRUE` was absent and
it could never act as a trust anchor no matter what any node was told -- and it
was pinned into node userData anyway, where it did precisely nothing. A leaf
issued here cannot have that shape.

USAGE

  values:
    trust:
      enabled: true
      domain:  camelot
      issuer:  camelot-ca-issuer          # ClusterIssuer of kind `ca`
      caSecret: camelot-ca-secret         # holds ca.crt (the anchor)
      anchor:  "3F:EC:8A:..."             # asserted by `trust verify`, not here
      dnsNames: [svc.ns.svc.cluster.local]

  templates/certificate.yaml:   {{- include "pleme-lib.trust.certificate" . }}
  in the podSpec:               {{- include "pleme-lib.trust.volume" . | nindent 6 }}
  in each container:            {{- include "pleme-lib.trust.volumeMount" . | nindent 10 }}
                                {{- include "pleme-lib.trust.env" . | nindent 10 }}
*/}}

{{/* Is the quality declared? Single source of truth for every helper below. */}}
{{- define "pleme-lib.trust.enabled" -}}
{{- if and .Values.trust (.Values.trust).enabled -}}true{{- else -}}false{{- end -}}
{{- end }}

{{- define "pleme-lib.trust.caSecret" -}}
{{- $t := .Values.trust | default dict -}}
{{- $t.caSecret | default (printf "%s-ca-secret" ($t.domain | default "pleme")) -}}
{{- end }}

{{/*
Where the anchor lands in the container. A single-file bundle, NOT a directory:
SSL_CERT_FILE takes a file and SSL_CERT_DIR takes a hashed directory, and a
directory handed to SSL_CERT_FILE fails open on some stacks and closed on
others. One shape, stated once.
*/}}
{{- define "pleme-lib.trust.caPath" -}}
/etc/pleme/trust/ca.crt
{{- end }}

{{/*
Fail loudly on a declaration that cannot work. Every one of these is a
misconfiguration that otherwise renders green and trusts nothing.
*/}}
{{- define "pleme-lib.trust.validate" -}}
{{- if eq (include "pleme-lib.trust.enabled" .) "true" -}}
  {{- $t := .Values.trust -}}
  {{- if not $t.domain -}}
    {{- fail "trust: `trust.domain` is required when trust.enabled (SC-17) -- an anchor with no domain cannot be verified against a declared fingerprint" -}}
  {{- end -}}
  {{- if not $t.issuer -}}
    {{- fail (printf "trust: `trust.issuer` is required for domain %q (SC-17); leaves must come from the domain issuer so a renewal chains to the anchor consumers already trust" $t.domain) -}}
  {{- end -}}
  {{- if $t.selfSigned -}}
    {{- fail "trust: `trust.selfSigned` is not supported and will not be added (SC-12). A SelfSigned issuer mints a NEW KEY on every install, so every pinned copy of the anchor is invalidated on the next cluster inception. Seed the CA and point `trust.issuer` at the domain's CA issuer." -}}
  {{- end -}}
  {{- if and $t.anchor (not (regexMatch "^([0-9A-F]{2}:){31}[0-9A-F]{2}$" ($t.anchor | toString))) -}}
    {{- fail (printf "trust: `trust.anchor` must be a colon-separated uppercase SHA256 fingerprint (the shape `openssl x509 -noout -fingerprint -sha256` emits), got %q" $t.anchor) -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
The leaf. isCA is FALSE and stated rather than defaulted, because the defect
that motivated this template was a cert whose basicConstraints were absent
entirely -- and "absent" is not the same claim as "false" to a reader.
*/}}
{{- define "pleme-lib.trust.certificate" -}}
{{- include "pleme-lib.trust.validate" . -}}
{{- if eq (include "pleme-lib.trust.enabled" .) "true" -}}
{{- $t := .Values.trust -}}
{{- $fullname := include "pleme-lib.fullname" . -}}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $fullname }}-trust
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
    trust.pleme.io/domain: {{ $t.domain | quote }}
  annotations:
    {{- include "pleme-lib.trust.anchorAnnotations" . | nindent 4 }}
spec:
  isCA: false
  secretName: {{ $t.certSecret | default (printf "%s-trust-tls" $fullname) }}
  dnsNames:
    {{- if $t.dnsNames }}
    {{- toYaml $t.dnsNames | nindent 4 }}
    {{- else }}
    - {{ printf "%s.%s.svc.cluster.local" $fullname .Release.Namespace }}
    - {{ $fullname }}
    {{- end }}
  usages:
    - server auth
    - digital signature
    - key encipherment
  privateKey:
    algorithm: {{ $t.keyAlgorithm | default "RSA" }}
    size: {{ $t.keySize | default 4096 }}
  issuerRef:
    name: {{ $t.issuer }}
    kind: {{ $t.issuerKind | default "ClusterIssuer" }}
    group: cert-manager.io
{{- end -}}
{{- end }}

{{/*
The handoff to `trust verify`. Helm cannot compute a fingerprint -- Go templates
have no digest function -- so it cannot check that the mounted anchor is the
declared one. It records the claim instead, and the tool checks it against the
live Secret and every other pinned copy. Recording an unverifiable claim is only
honest because something else verifies it; these annotations are what that
something else reads.
*/}}
{{- define "pleme-lib.trust.anchorAnnotations" -}}
{{- $t := .Values.trust | default dict -}}
trust.pleme.io/domain: {{ $t.domain | default "" | quote }}
trust.pleme.io/ca-secret: {{ include "pleme-lib.trust.caSecret" . | quote }}
{{- if $t.anchor }}
trust.pleme.io/anchor-sha256: {{ $t.anchor | quote }}
{{- end }}
{{- end }}

{{- define "pleme-lib.trust.volume" -}}
{{- if eq (include "pleme-lib.trust.enabled" .) "true" -}}
- name: pleme-trust-ca
  secret:
    secretName: {{ include "pleme-lib.trust.caSecret" . }}
    items:
      - key: ca.crt
        path: ca.crt
{{- end -}}
{{- end }}

{{- define "pleme-lib.trust.volumeMount" -}}
{{- if eq (include "pleme-lib.trust.enabled" .) "true" -}}
- name: pleme-trust-ca
  mountPath: {{ dir (include "pleme-lib.trust.caPath" .) }}
  readOnly: true
{{- end -}}
{{- end }}

{{/*
Propagate the anchor to the runtimes that actually read it.

SSL_CERT_FILE REPLACES the bundle for OpenSSL rather than adding to it, so a
bare private CA there breaks every PUBLIC TLS call the workload makes -- and it
breaks it as a verification error at the far end, which reads as an outage in a
dependency. `trust.replaceSystemBundle` therefore defaults false and the private
anchor is exposed under its own variable, leaving the system bundle intact.
Set it true only for a workload that talks to nothing outside the mesh.
*/}}
{{- define "pleme-lib.trust.env" -}}
{{- if eq (include "pleme-lib.trust.enabled" .) "true" -}}
{{- $t := .Values.trust -}}
{{- $path := include "pleme-lib.trust.caPath" . -}}
- name: PLEME_TRUST_CA
  value: {{ $path | quote }}
- name: NODE_EXTRA_CA_CERTS
  value: {{ $path | quote }}
- name: REQUESTS_CA_BUNDLE
  value: {{ $path | quote }}
{{- if $t.replaceSystemBundle }}
- name: SSL_CERT_FILE
  value: {{ $path | quote }}
{{- end }}
{{- end -}}
{{- end }}
