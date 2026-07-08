{{/*
lareira-camelot-observe — named-template seams shared by dashboards.yaml +
alerts.yaml. This cell emits ONLY pangea-operator CRs; there is no workload
template, hence no `.fullname` / `.serviceAccountName` (nothing is scheduled).
*/}}

{{/*
Standard metadata labels stamped on every CR this cell emits. `pleme.io/cell`
carries the instantiation key (observe.env) so a fleet query can scope to one
cell. Call with the ROOT context: include "lareira-camelot-observe.labels" $root
*/}}
{{- define "lareira-camelot-observe.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: pleme-io
pleme.io/cell: {{ .Values.observe.env | quote }}
{{- end -}}

{{/*
The per-cell compliance overlay MARKER — the `compliance.pleme.io/*` annotation
block for the declared overlay set (observe compliance.overlays, e.g.
fedramp-high, which cascades fedramp-moderate + fedramp-low). SHADOW-FIRST: this
stamps ONLY the annotations surface — it does NOT invoke the overlay `validate`
surface (this cell has no pods to validate, and compliance.enforce=false).
Delegates to the pleme-lib overlay dispatch (the canonical compliance seam);
`| trim` removes the dispatch's leading/trailing newline so nindent is clean.
Call with the ROOT context.
*/}}
{{- define "lareira-camelot-observe.complianceAnnotations" -}}
{{- include "pleme-lib.overlay.dispatchAll" (list "annotations" .) | trim -}}
{{- end -}}

{{/*
Resolve + validate the cell's routing destination ONCE (the luis|akeyless|2f
enum guard). A bad observe.routing.destination fail()s render here, via the
shared pleme-lib.routing seam. Call with the ROOT context; returns the echoed
destination string.
*/}}
{{- define "lareira-camelot-observe.dest" -}}
{{- include "pleme-lib.routing.destination" (dict "destination" .Values.observe.routing.destination "ctx" (printf "camelot-observe/%s" .Values.observe.env)) -}}
{{- end -}}
