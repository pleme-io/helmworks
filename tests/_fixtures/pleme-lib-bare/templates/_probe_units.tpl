{{/* Probe units: exist only to exercise pleme-lib.registry.* in tests. */}}
{{- define "probe.unit.alpha.requires" -}}{{- end }}
{{- define "probe.unit.beta.requires" -}}alpha{{- end }}
{{- define "probe.unit.gamma.requires" -}}beta{{- end }}
{{- define "probe.unit.cycle.requires" -}}cycle{{- end }}
{{- define "probe.unit.dangling.requires" -}}nonexistent{{- end }}
{{- define "probe.unit.alpha.mark" -}}A{{- end }}
{{- define "probe.unit.beta.mark" -}}B{{- end }}
{{- define "probe.unit.gamma.mark" -}}G{{- end }}
