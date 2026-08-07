{{/*
pleme-lib.scaleToZero.v1 — declare scale-to-zero as a QUALITY, not a mechanism.

WHY A VERSIONED NAME. Helm's named-template namespace is global and flat, so a
chart that vendors several pleme-lib copies resolves `pleme-lib.<name>` to
whichever `.tpl` is parsed last. An older copy that lacks the define renders
NOTHING, silently, exit 0 — measured in this repo: 116 vendored pleme-lib
tarballs at 17 distinct versions, 96 of 108 in-chart copies still pre-fix.
`.v1` cannot be shadowed by a copy that does not define it, and if EVERY copy in
the graph is old the include fails the render. Silent-nothing becomes a loud
failure. Never rename this template; add `.v2` beside it.

WHAT THIS IS NOT. It is not a breathe dimension. breathe owns proportional
scaling (N<->M) on both axes; scale-to-zero is ACTIVATION (0<->1), a different
law — and breathe's own `LifecycleDecision::ScaleToZero => (None, true)` routes
zero outward to the scaler rather than writing it. It is also not park: park is
an operator-asserted floor override that must WIN over any autoscaler, which is
why this template emits an annotations block (below) so `paused-replicas` can
reach the object it renders.

THE ONE DISTINCTION THAT MATTERS. Whether demand is observable while the
workload does not exist. A durable queue's depth is pollable from outside at
zero, which is why the `queue` arm wakes natively. HTTP is not — it needs an
interceptor to hold the connection and manufacture durability. Cron cannot wake
on demand at all. The arm names the contract, and exactly one must be chosen.

Usage:
  {{- include "pleme-lib.scaleToZero.v1" . }}

Values:
  scaleToZero:
    enabled: true
    target:
      kind: Deployment          # Deployment | StatefulSet
      name: ""                  # default: pleme-lib.fullname
    bounds:
      min: 0                    # 0 = true zero
      max: 4
    wake:
      kind: queue               # exactly one arm; zero or two is a render error
      queue:
        broker: nats-jetstream
        url: "nats://pleme-nats.camelot-nats.svc:4222"
        account: "$G"
        stream: BUILD
        consumer: builder
        lagThreshold: "1"
        activationLagThreshold: "0"
    rest:
      cooldownSeconds: 300
      pollingIntervalSeconds: 15
    annotations: {}             # reaches metadata.annotations — park needs this
    labels: {}                  # merged LAST, so part-of is overridable
*/}}

{{/*
Numeric read that survives zero.

Sprig's `default` treats integer 0 as empty, so `default 4 $b.max` silently
rewrites `max: 0` to 4 and `default 300 $b.cooldown` rewrites `cooldown: 0` to
300 — both live in _breathability.tpl today. `kindIs "invalid"` is a nil check
rather than an emptiness check, and it is the idiom pleme-lib already uses in
_deployment.tpl for exactly this reason.

Args: (list <value> <fallback>)
*/}}
{{- define "pleme-lib.scaleToZero.num" -}}
{{- $v := index . 0 -}}
{{- $fallback := index . 1 -}}
{{- if kindIs "invalid" $v -}}{{- $fallback -}}{{- else -}}{{- $v -}}{{- end -}}
{{- end -}}

{{- define "pleme-lib.scaleToZero.v1" -}}
{{- $g := .Values.global | default dict }}
{{- $s := .Values.scaleToZero | default $g.scaleToZero | default dict }}
{{- if $s.enabled }}

{{- /* ── exactly one wake arm ──────────────────────────────────────────────
     Zero arms or two is a RENDER FAILURE, not a silent no-op. A workload that
     declares scale-to-zero and renders no scaler is the failure mode this whole
     design exists to make impossible: it looks configured, reports healthy, and
     never scales. Precedent: pleme-arc-runner-pool/templates/pause-state.yaml
     already refuses `paused: true` unpaired with min/maxRunners = 0. */ -}}
{{- $wake := $s.wake | default dict }}
{{- $arms := list }}
{{- range $k := (list "queue" "http" "cron" "custom") }}
  {{- if hasKey $wake $k }}{{- $arms = append $arms $k }}{{- end }}
{{- end }}
{{- if ne (len $arms) 1 }}
{{- fail (printf "scaleToZero.wake must declare EXACTLY ONE arm (queue|http|cron|custom); found %d: %v. Zero arms renders no scaler while the workload reports healthy — the exact silent failure this template refuses." (len $arms) $arms) }}
{{- end }}
{{- $arm := first $arms }}
{{- if and $s.wake.kind (ne $s.wake.kind $arm) }}
{{- fail (printf "scaleToZero.wake.kind is %q but the arm present is %q — the declaration contradicts itself" $s.wake.kind $arm) }}
{{- end }}

{{- /* ── P0 scope: the queue arm only ─────────────────────────────────────
     http/cron/custom land in P1+. Failing loudly beats emitting a partially
     configured scaler that never wakes. */ -}}
{{- if ne $arm "queue" }}
{{- fail (printf "scaleToZero.wake.%s is not implemented in scaleToZero.v1 yet (P0 ships the queue arm). Use pleme-lib.breathability for now, or wait for P1." $arm) }}
{{- end }}

{{- /* ── the replicas conflict, refused rather than inherited ─────────────
     `_deployment.tpl` gates spec.replicas on .Values.autoscaling.enabled — a
     DIFFERENT values tree. A chart with autoscaling.enabled AND scaleToZero
     targeting its own workload renders a hard replicas value that Helm and KEDA
     then fight over on every reconcile. pleme-sui and pleme-nix-builder are
     both in that state today under the old template. */ -}}
{{- if and (.Values.autoscaling).enabled (not $s.target.name) }}
{{- fail "scaleToZero and autoscaling.enabled both own this chart's own workload replicas — Helm and KEDA will fight over spec.replicas every reconcile. Set autoscaling.enabled=false, or point scaleToZero.target.name at a different workload." }}
{{- end }}

{{- $fullname := include "pleme-lib.fullname" . }}
{{- $target := $s.target | default dict }}
{{- $targetName := default $fullname $target.name }}
{{- $targetKind := default "Deployment" $target.kind }}
{{- $bounds := $s.bounds | default dict }}
{{- $rest := $s.rest | default dict }}
{{- $q := $wake.queue }}
---
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ $fullname }}
  labels:
    {{- /* MERGED as maps, not appended as text. pleme-lib.labels hardcodes
           app.kubernetes.io/part-of: nexus-platform, so emitting an override
           after it produces a DUPLICATE KEY that strict YAML rejects outright
           ("mapping key already defined") — proven by this template's own test
           suite before this was a merge. Sprig's `merge` gives precedence to
           the destination, so consumer labels win and exactly one key is
           emitted. */ -}}
    {{- $base := fromYaml (include "pleme-lib.labels" .) }}
    {{- $labels := merge (deepCopy ($s.labels | default dict)) $base }}
    {{- toYaml $labels | nindent 4 }}
  {{- /* park reaches the object through here. A shared partial that cannot
         carry autoscaling.keda.sh/paused-replicas is unusable fleet-wide,
         because park must win over any autoscaler. */ -}}
  {{- with $s.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  scaleTargetRef:
    kind: {{ $targetKind }}
    name: {{ $targetName }}
  minReplicaCount: {{ include "pleme-lib.scaleToZero.num" (list $bounds.min 0) }}
  maxReplicaCount: {{ include "pleme-lib.scaleToZero.num" (list $bounds.max 4) }}
  cooldownPeriod: {{ include "pleme-lib.scaleToZero.num" (list $rest.cooldownSeconds 300) }}
  pollingInterval: {{ include "pleme-lib.scaleToZero.num" (list $rest.pollingIntervalSeconds 15) }}
  triggers:
    - type: {{ default "nats-jetstream" $q.broker }}
      metadata:
        natsServerMonitoringEndpoint: {{ required "scaleToZero.wake.queue.url is required" $q.url | replace "nats://" "" | replace ":4222" ":8222" | quote }}
        account: {{ default "$G" $q.account | quote }}
        stream: {{ required "scaleToZero.wake.queue.stream is required" $q.stream | quote }}
        consumer: {{ required "scaleToZero.wake.queue.consumer is required" $q.consumer | quote }}
        lagThreshold: {{ default "1" $q.lagThreshold | quote }}
        activationLagThreshold: {{ default "0" $q.activationLagThreshold | quote }}
{{- end }}
{{- end }}

{{/*
pleme-lib.scaleToZero.replicasField — emit `replicas: N`, or nothing at all.

When scaleToZero owns a workload, the workload must NOT carry a hard replicas
field: KEDA owns it from minReplicaCount onward, and a rendered value makes Helm
and KEDA fight on every reconcile. When it does emit, it must survive zero —
`.Values.replicaCount | default 1` silently substituted a nonzero value in three
separate charts (pleme-lib <=0.40.1, pleme-zot <=0.3.3 which ALSO carried a
`minimum: 1` schema, and the upstream ARC controller chart which accepts 0 and
ignores it). pleme-zot's commit records the field symptom: "the release sat
UpgradeFailed and zot kept running at 1/1 through a full park."

Usage, inside a Deployment/StatefulSet spec:
  {{- include "pleme-lib.scaleToZero.replicasField" . | nindent 2 }}
*/}}
{{- define "pleme-lib.scaleToZero.replicasField" -}}
{{- $g := .Values.global | default dict }}
{{- $s := .Values.scaleToZero | default $g.scaleToZero | default dict }}
{{- if $s.enabled }}
{{- /* KEDA owns it from here — emit nothing. */ -}}
{{- else if (.Values.autoscaling).enabled }}
{{- /* the HPA owns it — emit nothing. */ -}}
{{- else if kindIs "invalid" .Values.replicaCount }}
replicas: 1
{{- else }}
replicas: {{ .Values.replicaCount }}
{{- end }}
{{- end }}
