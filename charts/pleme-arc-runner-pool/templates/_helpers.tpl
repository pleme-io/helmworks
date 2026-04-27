{{/*
pleme-arc-runner-pool: chart-specific helpers. Most rendering delegates to
pleme-lib helpers via `{{ include "pleme-lib.*" . }}`; only chart-local
concepts (the typed pause contract) live here.
*/}}

{{/*
Validate the typed pause contract.

Helm subchart values can't be computed by parent templates at render time —
the parent's value-merge happens before template processing. Pause is therefore
a TYPED CONTRACT: when `paused: true`, the operator MUST set both
`gha-runner-scale-set.minRunners` and `gha-runner-scale-set.maxRunners` to 0.

This helper fails the install (`helm.sh/fail`) if the two are out of sync.
The check fires from any template that includes it, so a single render-time
invocation in `pause-state.yaml` is enough — `helm template`, `helm install`,
helm-unittest, and Flux's reconciliation all surface the failure with a clear
message.

The `paused: false → maxRunners > 0` direction is NOT enforced — operators are
free to set maxRunners=0 with paused=false during transient bring-up.
*/}}
{{- define "pleme-arc-runner-pool.validatePause" -}}
{{- if .Values.paused -}}
{{- $upstream := index .Values "gha-runner-scale-set" | default dict -}}
{{- $minR := default 0 (get $upstream "minRunners") -}}
{{- $maxR := default 0 (get $upstream "maxRunners") -}}
{{- if or (gt ($minR | int) 0) (gt ($maxR | int) 0) -}}
{{- fail (printf "pleme-arc-runner-pool: paused=true requires gha-runner-scale-set.minRunners=0 AND gha-runner-scale-set.maxRunners=0 (got minRunners=%v maxRunners=%v). The listener stays running so GitHub jobs queue but never spin up runners — both runner counts MUST be zero or the contract is violated. Set both to 0 in the same git commit as paused=true." $minR $maxR) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Pause-aware annotations: emits `pleme.io/paused: "true"` and a reason annotation
when `paused: true`, otherwise empty. Other charts can adopt the same convention.
*/}}
{{- define "pleme-arc-runner-pool.pauseAnnotations" -}}
{{- if .Values.paused -}}
pleme.io/paused: "true"
pleme.io/paused-reason: {{ default "operator-set" .Values.pausedReason | quote }}
{{- end -}}
{{- end -}}

{{/*
Pause-aware label: emits `pleme.io/paused: "true"` when paused. Useful for
selecting paused pools via `kubectl get ... -l pleme.io/paused=true`.
*/}}
{{- define "pleme-arc-runner-pool.pauseLabels" -}}
{{- if .Values.paused -}}
pleme.io/paused: "true"
{{- end -}}
{{- end -}}
