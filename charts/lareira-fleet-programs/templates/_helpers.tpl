{{- define "lareira-fleet-programs.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "lareira-fleet-programs.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: lareira-fleet
{{- end -}}

{{/*
Validate a single program entry. Returns "" if OK, or an error message.
*/}}
{{- define "lareira-fleet-programs.validate-entry" -}}
{{- $p := . -}}
{{- if not $p.name -}}{{ fail "fleet program: every entry needs `name`" }}{{- end -}}
{{- if not $p.module -}}{{ fail (printf "fleet program %q: missing `module`" $p.name) }}{{- end -}}
{{- if and (not $p.module.source) (not $p.module.oci) -}}
{{- fail (printf "fleet program %q: module needs source: or oci:" $p.name) -}}
{{- end -}}
{{- if not $p.trigger -}}{{ fail (printf "fleet program %q: missing `trigger`" $p.name) }}{{- end -}}
{{- $shapeCount := 0 -}}
{{- range $k, $v := $p.trigger -}}
{{- if and (or (eq $k "oneShot") (eq $k "cron") (eq $k "service") (eq $k "event") (eq $k "watch")) $v -}}
{{- $shapeCount = add $shapeCount 1 -}}
{{- end -}}
{{- end -}}
{{- if ne $shapeCount 1 -}}
{{- fail (printf "fleet program %q: exactly one trigger shape required, got %d" $p.name $shapeCount) -}}
{{- end -}}
{{- end -}}

{{/*
Resolve the shape of a program entry — same logic as pleme-computeunit
but reading from the iterated entry rather than .Values.
*/}}
{{- define "lareira-fleet-programs.shape" -}}
{{- $t := .trigger -}}
{{- if $t.oneShot -}}program{{- else if $t.cron -}}job{{- else if $t.service -}}service{{- else if $t.event -}}function{{- else if $t.watch -}}controller{{- else -}}invalid{{- end -}}
{{- end -}}
