{{/*
pleme-lib: compliance — admission policy emission

Aggregates the kyvernoPolicy + gatekeeperConstraint surface fragments
emitted by every applied overlay into a deployable manifest set. Charts
that want their compliance posture mirrored at the cluster admission
boundary include this template; the result is a stack of Kyverno
ClusterPolicy + Gatekeeper Constraint resources, each scoped to the
chart's namespace + selector.

Symmetric proof: chart-time validators reject non-compliant inputs
before render; cluster-side admission policies reject non-compliant
manifests at admission. Both sides flow from the SAME overlay declaration
so drift is impossible.

Usage in a chart that owns admission-policy emission (typically
pleme-compliance namespace chart, or a dedicated pleme-admission-policies
chart):

  templates/admission-policies.yaml:
    {{ include "pleme-lib.compliance.admissionPolicies" . }}
*/}}

{{- define "pleme-lib.compliance.admissionPolicies" -}}
{{- $kyverno := include "pleme-lib.overlay.dispatchDocuments" (list "kyvernoPolicy" .) | trim -}}
{{- $gk := include "pleme-lib.overlay.dispatchDocuments" (list "gatekeeperConstraint" .) | trim -}}
{{- if $kyverno -}}
{{ $kyverno }}
{{- end }}
{{- if $gk -}}
{{- if $kyverno }}
---
{{ end -}}
{{ $gk }}
{{- end }}
{{- end }}
