{{/*
pleme-lib hostname + ephemeral-identity primitives.

Solve-once home for the fleet hostname convention and the consistent
ephemeral-id hash. Every pleme-io chart that emits a hostname (Ingress
host, TLS SAN, DNSEndpoint, ExternalDNS annotation) renders it through
`pleme-lib.fleetHostname`; every chart that needs a deterministic
short identifier for an ephemeral environment derives it through
`pleme-lib.ephemeralId`. Hand-rolling either in a consuming chart is a
"solve-once" violation — extend these instead.

The org fleet convention (pleme-io/CLAUDE.md, lib/fleet-domains.nix):
    {app}.{cluster}.{location}.{domain}
The tatara ephemeral extension (apps/tatara routing):
    {app}.{eph_id}.{cluster}.{location}.{domain}
are both special cases of `pleme-lib.fleetHostname` below.
*/}}

{{/*
pleme-lib.ephemeralId — deterministic short identifier for an ephemeral environment.

Given an input string (an environment name, branch, PR ref, or a typed
spec digest), returns a stable lowercase 8-hex-char id derived by
sha256-truncation. The same input always yields the same id, so the id
is reproducible across renders and safe to embed in a DNS label that
must stay consistent for the lifetime of the ephemeral environment —
exactly the "consistent hash identifier scoped to the hosted zone"
contract.

This is the chart-side analogue of tatara's BLAKE3(spec)[:8] eph_id.
The algorithm differs (Helm has no blake3) but the contract is the
same: deterministic, short, DNS-label-safe. When tatara drives the
deployment it passes its own eph_id straight through as `ephemeral`;
this helper is for charts that must derive their own id from a name.

Args: the input string as the dot context, e.g.
  {{ include "pleme-lib.ephemeralId" "my-feature-branch" }}
Returns: 8 lowercase hex chars, e.g. "9f8e7d6c".
Fails when the input is empty (a typed error beats a silent wrong id).
*/}}
{{- define "pleme-lib.ephemeralId" -}}
{{- $in := . | toString -}}
{{- if eq $in "" -}}
{{- fail "pleme-lib.ephemeralId: input string is required (got empty)" -}}
{{- end -}}
{{- sha256sum $in | trunc 8 -}}
{{- end -}}

{{/*
pleme-lib.fleetHostname — render a fleet-convention hostname.

Full superset pattern:
  {app}[-{instance}][.{ephemeral}][.{cluster}][.{location}].{domain}

Empty instance/ephemeral/cluster/location segments collapse out, so one
call degrades cleanly from a 5-part ephemeral host down to a 2-part
Cloudflare-Universal-SSL host depending on which segments are supplied:

  app=akeyless-saas domain=quero.lol cluster=pleme-dev location=use1
    -> akeyless-saas.pleme-dev.use1.quero.lol            (named, org convention)
  + ephemeral=9f8e7d6c
    -> akeyless-saas.9f8e7d6c.pleme-dev.use1.quero.lol   (ephemeral, tatara-aligned)
  + instance=test01 (no ephemeral)
    -> akeyless-saas-test01.pleme-dev.use1.quero.lol     (legacy leaf-suffix form)
  app=akeyless-saas domain=quero.cloud (cluster/location "")
    -> akeyless-saas.quero.cloud                         (2-part, Universal SSL)

Args (dict):
  app       (required) — leaf component name, e.g. "akeyless-saas"
  instance  (optional) — leaf suffix; "" omits it
  ephemeral (optional) — consistent-hash segment (pleme-lib.ephemeralId); "" omits it
  cluster   (optional) — cluster segment; "" omits it
  location  (optional) — location / sub-zone segment; "" omits it
  domain    (required) — hosted-zone root, e.g. "quero.lol"

Fails when app or domain is empty.
*/}}
{{- define "pleme-lib.fleetHostname" -}}
{{- $app := .app | default "" | toString -}}
{{- $instance := .instance | default "" | toString -}}
{{- $ephemeral := .ephemeral | default "" | toString -}}
{{- $cluster := .cluster | default "" | toString -}}
{{- $location := .location | default "" | toString -}}
{{- $domain := .domain | default "" | toString -}}
{{- if eq $app "" -}}{{- fail "pleme-lib.fleetHostname: app is required" -}}{{- end -}}
{{- if eq $domain "" -}}{{- fail "pleme-lib.fleetHostname: domain is required" -}}{{- end -}}
{{- $leaf := $app -}}
{{- if ne $instance "" -}}{{- $leaf = printf "%s-%s" $app $instance -}}{{- end -}}
{{- $segments := list $leaf -}}
{{- if ne $ephemeral "" -}}{{- $segments = append $segments $ephemeral -}}{{- end -}}
{{- if ne $cluster "" -}}{{- $segments = append $segments $cluster -}}{{- end -}}
{{- if ne $location "" -}}{{- $segments = append $segments $location -}}{{- end -}}
{{- $segments = append $segments $domain -}}
{{- join "." $segments -}}
{{- end -}}
