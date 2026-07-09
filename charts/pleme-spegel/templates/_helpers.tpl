{{/*
pleme-spegel local helpers.

Composes the shipped pleme-lib helpers (name / fullname / namespace / labels /
selectorLabels) — never re-rolls them — and adds only what pleme-lib does not
provide: a DIGEST-AWARE image ref (pleme-lib.image is tag-only) and the stable
service names the DNS bootstrap contract depends on.
*/}}

{{/*
pleme-spegel.image — the ADOPTED upstream image ref, digest-pinned when set.

Adopt-not-fork: this resolves ghcr.io/spegel-org/spegel@<digest> when
`.Values.image.digest` is present (the hermetic, attested destination), else
falls back to repository:tag. pleme-lib.image cannot express a digest pin, so
this is the one local override — still config-only, still the upstream binary.
*/}}
{{- define "pleme-spegel.image" -}}
{{- $repo := .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion | default "latest" -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}

{{/*
pleme-spegel.serviceAccountName — the SA the DaemonSet runs as.
*/}}
{{- define "pleme-spegel.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "pleme-lib.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
pleme-spegel.bootstrapService — the headless Service the router's dns-bootstrap
resolves peers through. Stable name is load-bearing: the DaemonSet's
--dns-bootstrap-domain flag is derived from it, so both MUST agree.
*/}}
{{- define "pleme-spegel.bootstrapService" -}}
{{- printf "%s-bootstrap" (include "pleme-lib.fullname" .) -}}
{{- end -}}

{{/*
pleme-spegel.registryService — the NodePort Service exposing the mirror as a
cross-node target.
*/}}
{{- define "pleme-spegel.registryService" -}}
{{- printf "%s-registry" (include "pleme-lib.fullname" .) -}}
{{- end -}}

{{/*
pleme-spegel.dnsBootstrapDomain — the FQDN the router uses for dns-bootstrap.
*/}}
{{- define "pleme-spegel.dnsBootstrapDomain" -}}
{{- printf "%s.%s.svc.%s" (include "pleme-spegel.bootstrapService" .) (include "pleme-lib.namespace" .) (.Values.clusterDomain | default "cluster.local") -}}
{{- end -}}
