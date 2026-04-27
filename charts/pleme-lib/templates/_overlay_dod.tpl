{{/*
Overlays: dod-il2 / dod-il4 / dod-il5 / dod-il6
Source: DoD Cloud Computing SRG v1r4 (Jan 2022); CNSSI 1253

Each level layers cumulatively on top of the prior — il5 requires il4
requires il2 — but the impact of each level is expressed as its own
overlay so the proof chain is explicit. dod-il5 = dod-il4 + IL5 deltas;
dod-il6 = dod-il5 + IL6 deltas.
*/}}

{{/* ───────────────────────────── dod-il2 ─────────────────────────── */}}

{{- define "pleme-lib.overlay.dod-il2.requires" -}}fedramp-moderate{{- end }}

{{- define "pleme-lib.overlay.dod-il2.controls" -}}
DoD-CC-SRG-IL2
{{- end }}

{{- define "pleme-lib.overlay.dod-il2.validate" -}}
{{/* IL2 = FedRAMP Moderate equivalent. The require fedramp-moderate
     handles the substantive controls; this overlay only annotates the
     DoD impact-level claim. */}}
{{- end }}

{{- define "pleme-lib.overlay.dod-il2.annotations" -}}
compliance.pleme.io/overlay-dod-il2: "true"
pleme.io/dod-impact-level: "il2"
pleme.io/dod-srg-version: "v1r4"
{{ end }}

{{- define "pleme-lib.overlay.dod-il2.labels" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il2.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.dod-il2.manifestData" -}}
overlay-dod-il2: "true"
{{- $list := include "pleme-lib.overlay.list" . | fromYamlArray -}}
{{- if not (or (or (has "dod-il6" $list) (has "dod-il5" $list)) (has "dod-il4" $list)) }}
dod-impact-level: "il2"
dod-srg-version: "v1r4"
{{- end }}
{{ end }}

{{- define "pleme-lib.overlay.dod-il2.podEnv" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il2.imagePullSecrets" -}}{{- end }}


{{/* ───────────────────────────── dod-il4 ─────────────────────────── */}}

{{- define "pleme-lib.overlay.dod-il4.requires" -}}fedramp-moderate,airgap-consumer{{- end }}

{{- define "pleme-lib.overlay.dod-il4.controls" -}}
DoD-CC-SRG-IL4
{{- end }}

{{- define "pleme-lib.overlay.dod-il4.validate" -}}
{{/* IL4 forces airgap (registry boundary for CUI). The requires field
     handles the cascade; the validator here only checks that
     compliance.dod.impactLevel matches if set. */}}
{{- $il := include "pleme-lib.compliance.dod.impactLevel" . -}}
{{- if and $il (ne $il "il4") (ne $il "il5") (ne $il "il6") -}}
  {{- fail (printf "compliance: overlay dod-il4 declared but compliance.dod.impactLevel=%q (expected il4 or higher)" $il) -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.overlay.dod-il4.annotations" -}}
compliance.pleme.io/overlay-dod-il4: "true"
pleme.io/dod-impact-level: "il4"
pleme.io/dod-srg-version: "v1r4"
{{ end }}

{{- define "pleme-lib.overlay.dod-il4.labels" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il4.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.dod-il4.manifestData" -}}
overlay-dod-il4: "true"
{{- $list := include "pleme-lib.overlay.list" . | fromYamlArray -}}
{{- if not (or (has "dod-il6" $list) (has "dod-il5" $list)) }}
dod-impact-level: "il4"
dod-srg-version: "v1r4"
{{- end }}
{{ end }}

{{- define "pleme-lib.overlay.dod-il4.podEnv" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il4.imagePullSecrets" -}}{{- end }}


{{/* ───────────────────────────── dod-il5 ─────────────────────────── */}}

{{- define "pleme-lib.overlay.dod-il5.requires" -}}fedramp-high,airgap-consumer,supplychain,fips{{- end }}

{{- define "pleme-lib.overlay.dod-il5.controls" -}}
DoD-CC-SRG-IL5
{{- end }}

{{- define "pleme-lib.overlay.dod-il5.validate" -}}
{{- include "pleme-lib.compliance.dod.validate" . -}}
{{- end }}

{{- define "pleme-lib.overlay.dod-il5.annotations" -}}
compliance.pleme.io/overlay-dod-il5: "true"
pleme.io/dod-impact-level: "il5"
pleme.io/dod-srg-version: "v1r4"
{{ end }}

{{- define "pleme-lib.overlay.dod-il5.labels" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il5.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.dod-il5.manifestData" -}}
overlay-dod-il5: "true"
{{- $list := include "pleme-lib.overlay.list" . | fromYamlArray -}}
{{- if not (has "dod-il6" $list) }}
dod-impact-level: "il5"
dod-srg-version: "v1r4"
{{- end }}
{{ end }}

{{- define "pleme-lib.overlay.dod-il5.podEnv" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il5.imagePullSecrets" -}}{{- end }}


{{/* ───────────────────────────── dod-il6 ─────────────────────────── */}}

{{- define "pleme-lib.overlay.dod-il6.requires" -}}fedramp-high,airgap-consumer,supplychain,fips,dod-il5{{- end }}

{{- define "pleme-lib.overlay.dod-il6.controls" -}}
DoD-CC-SRG-IL6,SC-12(2),SR-11(2)
{{- end }}

{{- define "pleme-lib.overlay.dod-il6.validate" -}}
{{- include "pleme-lib.compliance.dod.validate" . -}}
{{- end }}

{{- define "pleme-lib.overlay.dod-il6.annotations" -}}
compliance.pleme.io/overlay-dod-il6: "true"
pleme.io/dod-impact-level: "il6"
pleme.io/dod-srg-version: "v1r4"
{{ end }}

{{- define "pleme-lib.overlay.dod-il6.labels" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il6.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.dod-il6.manifestData" -}}
overlay-dod-il6: "true"
dod-impact-level: "il6"
dod-srg-version: "v1r4"
{{ end }}

{{- define "pleme-lib.overlay.dod-il6.podEnv" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il6.imagePullSecrets" -}}{{- end }}

{{/* DoD admission policies: empty here (the cascade through fedramp-*
     and supplychain + fips overlays produces all admission policies).
     IL5/IL6-specific policies (e.g. CDS-only egress) would go here. */}}
{{- define "pleme-lib.overlay.dod-il2.kyvernoPolicy" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il2.gatekeeperConstraint" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il4.kyvernoPolicy" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il4.gatekeeperConstraint" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il5.kyvernoPolicy" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il5.gatekeeperConstraint" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il6.kyvernoPolicy" -}}{{- end }}
{{- define "pleme-lib.overlay.dod-il6.gatekeeperConstraint" -}}{{- end }}
