{{/*
Overlay: mirror

Generic scheduled-sync overlay. The airgap-registry-mirror overlay also
delegates to this overlay's helpers (mirror.validate, mirror.manifestData)
because both shapes need the same checks; mirror exists as a standalone
overlay for charts using mirror primitives WITHOUT taking the air-gap
registry-mirror role (e.g. helm-mirror, policy-mirror, sbom-mirror).

Source: NIST 800-53 AU-2/3/12, IA-5, SI-7, CM-2, SR-3/4
*/}}

{{- define "pleme-lib.overlay.mirror.requires" -}}{{- end }}

{{- define "pleme-lib.overlay.mirror.controls" -}}
AU-2,AU-3,AU-12,IA-5,SI-7,SR-3,SR-4
{{- end }}

{{- define "pleme-lib.overlay.mirror.validate" -}}
{{- include "pleme-lib.compliance.mirror.validate" . -}}
{{- end }}

{{- define "pleme-lib.overlay.mirror.annotations" -}}
compliance.pleme.io/overlay-mirror: "true"
{{ end }}

{{- define "pleme-lib.overlay.mirror.labels" -}}{{- end }}
{{- define "pleme-lib.overlay.mirror.policies" -}}{{- end }}

{{- define "pleme-lib.overlay.mirror.manifestData" -}}
overlay-mirror: "true"
{{ include "pleme-lib.compliance.mirror.manifestData" . | trim }}
{{ end }}

{{- define "pleme-lib.overlay.mirror.podEnv" -}}{{- end }}
{{- define "pleme-lib.overlay.mirror.imagePullSecrets" -}}{{- end }}

{{- define "pleme-lib.overlay.mirror.kyvernoPolicy" -}}{{- end }}
{{- define "pleme-lib.overlay.mirror.gatekeeperConstraint" -}}{{- end }}
