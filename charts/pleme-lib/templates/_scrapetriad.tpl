{{/*
pleme-lib.scrapeTriad — emit the Service, the scrape CR and the port-scoped
NetworkPolicy hole AS ONE OBJECT, so having two of the three is unrepresentable.

★ THE TRAP THIS TEMPLATE EXISTS FOR: `up == 1` WITH THE SERIES ABSENT IS A
BROKEN SCRAPE, NOT A HEALTHY WORKLOAD — and the worse half is that a triad
missing one leg produces NO `up` series at all.

`up` is synthesised by the scraper for a target it already discovered. It says
the connection opened and the GET returned; it says nothing about what came
back. A handler that answers 200 with an empty body, collectors registered on a
registry the handler never reads, a relabel rule that dropped every series — all
read `up == 1` forever. So never alert on `up`; alert on `absent(<a series the
workload emits on every tick>)`, which is false only when the pipeline actually
works end to end.

Now the missing-leg case, which is worse because it is not even red. With no
Service there are no Endpoints, so the scrape CR selects nothing, so no target
is ever created, so there is no `up` series to be 0 and no target row to show
down. With no NetworkPolicy hole the target IS created and the scraper's
connection is refused — and the scrape reports THE TARGET as down, never naming
the policy as the cause, so the workload takes the blame for a firewall. Both
read as "nothing to see". Measured on one production cluster over a single week
(2026-07/08), the same missing-hole shape silently blackholed three separate
components' metrics; in each case the two other legs were already committed and
looked deployed.

Hence: one define, three objects, one values block. There is no supported way to
render a subset — except the declared `attach: pod` arm below, where the absence
of a Service is the point rather than an omission.

── WHAT THIS ENCODES ──────────────────────────────────────────────────────────

FLAVOUR IS A CLUSTER FACT, NOT A PREFERENCE, AND AN UNKNOWN ONE HARD-FAILS.
A cluster carries one metrics operator's CRDs, or the other's, or both. Applying
the wrong kind is not a degraded install: the API server rejects it, and where a
single reconciler owns the whole directory that rejection stalls every other
manifest beside it. So `flavour` is required and closed — an unknown value
fail()s at render. It must never degrade to emitting nothing, because emitting
nothing is precisely the outcome that looks deployed and reports healthy.

ONE LABEL SET, THREE ROLES, DERIVED — NEVER RESTATED.
The workload's own `spec.selector.matchLabels` is the single source for
  (a) the Service's metadata labels — how the scrape CR finds the Service,
  (b) the Service's spec.selector    — how the Service finds the pods,
  (c) the NetworkPolicy podSelector  — which pods the hole is opened on.
Two label sets free to disagree is the defect; a scrape whose selector was typed
out a second time can drift from the pods without anything failing. Taken from
the workload verbatim it cannot drift, because drifting would make the workload
itself unselectable. Default here is this chart's own `pleme-lib.selectorLabels`
— literally what `pleme-lib.deployment` renders into `spec.selector.matchLabels`
— so the common case reuses rather than restates. `selector` is an override for
the ATTACH case only: scraping a workload this chart does not own.

ONE PORT NUMBER, ONE MEANING.
`port` is the number the POD listens on. The Service publishes the same number
and targets it numerically; the netpol opens the same number. This deliberately
declines the usual named-`targetPort` advice, because a NetworkPolicy port is
evaluated at the POD while a Service port is not — the moment the Service remaps,
the hole is on a number nothing listens on and the failure is the silent one
above. One number cannot disagree with itself.

THE HOLE IS ADDITIVE, WHICH IS WHY IT SHIPS AS ITS OWN OBJECT.
A pod's allowed ingress is the UNION of every policy selecting it, so adding
this policy can never subtract from a namespace's existing default-deny or its
siblings. Rendering it here is byte-equivalent to hand-editing the namespace's
policy file, while keeping all three co-dependent pieces in one place — a later
revert or move that takes two and leaves the third is the failure worth
designing against.

AND IT IS SCOPED, NOT OPENED.
`scraperNamespaces` is REQUIRED and must be non-empty. An ingress rule with an
empty `namespaceSelector` matches EVERY namespace — that would hand every
workload on the cluster a read of this one's telemetry — and a selector built
from an empty string matches NOTHING, which is the silent blackhole again. Both
directions of the empty case are defects, so the empty case fail()s. The
membership is the consumer's to declare; this library never learns who scrapes.
(The `kubernetes.io/metadata.name` label the rule matches on is set by the API
server on every namespace, so no labelling step is implied.)

INTERVAL MUST SATISFY NYQUIST AGAINST THE ALERT WINDOW IT FEEDS.
An alert that evaluates over window W is asking a question about a signal of
period W, and a series sampled at ≥ W cannot express it: the alert fires on
whatever aliasing produced, or never fires at all, and either way the rule looks
correct in review. Gate: `intervalSeconds * 2 <= alertWindowSeconds`, i.e. at
least two samples inside the shortest window these series feed. `alertWindow`
is required precisely so the question "what is this scrape FOR" has to be
answered before the scrape exists — a scrape with no consumer is a cost, not a
signal.

Both periods are declared in SECONDS as integers, not as duration strings. A
string cannot be compared, so a gate over `"30s"` vs `"5m"` is either a parser
or a lie; the seconds are rendered back out as `<n>s` at emission.

WHAT THIS DELIBERATELY DOES NOT GATE: sampling faster than the PRODUCER's own
tick. Two independent operators derived opposite rules from the same premise —
one set the interval to half the controller's requeue period ("samples every
decision at Nyquist rather than aliasing across them"), the other set it equal
to the loop's tick ("scraping faster than the loop ticks re-reports the same
last-tick gauges and buys nothing"). Both are right about different metrics:
the first about a value that moves continuously between ticks, the second about
a gauge that is only rewritten on the tick. That is a per-workload judgement and
ossifying either one into a gate would be wrong, so it is recorded here and left
to the author. The alert-window rule above is a sampling theorem, not a taste,
which is why it is the one that fail()s.

── USAGE ──────────────────────────────────────────────────────────────────────

  {{- include "pleme-lib.scrapeTriad" (dict "ctx" .) }}

  # or, scraping a workload this chart does not own:
  {{- include "pleme-lib.scrapeTriad" (dict "ctx" . "triad" .Values.someOther) }}

  ctx    — the chart root context (required; supplies fullname/labels/namespace)
  triad  — the config dict; defaults to `.Values.scrapeTriad`

── VALUES ─────────────────────────────────────────────────────────────────────

  scrapeTriad:
    enabled: true
    flavour: vm              # vm | prometheus — REQUIRED, closed, unknown fails
    attach: service          # service | pod   — pod skips the Service (see below)
    port: 9464               # REQUIRED — the number the POD listens on
    portName: metrics        # service-arm: the Service port name this declares
                             # pod-arm:     the CONTAINER port name to scrape
    path: /metrics
    intervalSeconds: 30      # REQUIRED
    scrapeTimeoutSeconds: 10 # must be < intervalSeconds
    alertWindowSeconds: 300  # REQUIRED — shortest alert window these series feed
    scraperNamespaces:       # REQUIRED, non-empty — who is allowed to scrape
      - <the namespace your scraper runs in>
    selector: {}             # optional ATTACH override; default = this chart's
                             # own selectorLabels (what the Deployment renders)
    serviceName: ""          # default <fullname>-metrics
    name: ""                 # scrape CR name; default <fullname>
    headless: false          # true → clusterIP: None
    policyName: ""           # default <fullname>-allow-metrics-scrape

  attach: pod — for a workload with NO Service (a DaemonSet, a bare pod set).
  A Service-based scrape selects Services; with none to select it discovers
  nothing, which is the silent-nothing case again wearing a different hat. The
  pod-scrape kind is the shape that fits, and declaring `attach: pod` is what
  makes the missing Service a decision instead of an omission. The netpol leg is
  emitted unchanged — a Service-less workload is behind exactly the same
  default-deny.

  headless — a real ClusterIP is the default on purpose. Both scrape kinds
  discover via Endpoints and scrape pod IPs either way, so headless buys nothing
  at scrape time, while a routable address leaves a hand-debuggable target for
  the question you will actually be asking: "is it the scrape, or is it the
  target?"

OWNERSHIP BOUNDARY vs `pleme-lib._observabilityBundle` (read before adding a
third producer). Both emit scrape CRs; they are NOT redundant and must not be
merged:

  _observabilityBundle  emits a scrape CR, a PrometheusRule and dashboards for
                        a workload that is ALREADY reachable. It assumes the
                        Service exists and the network permits the scrape.
  scrapeTriad           emits the Service, the scrape CR and the port-scoped
                        NetworkPolicy hole TOGETHER, so two-of-three is
                        unrepresentable. It exists for the case where the
                        network is default-deny and the missing hole is why
                        `up == 1` shows no series.

Same goal, different shapes — so the rule is written here rather than forced
into one template that would fit neither (★★ CONVERGENT-EVIDENCE). A chart uses
ONE of them. If it uses both, the CR names no longer collide (this template
suffixes `-metrics`), but you will get two scrape CRs for one workload and
double the samples; that is a configuration mistake, not a supported layering.
*/}}

{{/* ── integer read that survives an explicit zero ──────────────────────────
     Sprig's `default` treats 0 as empty, so `default 10 $t.x` silently rewrites
     an authored 0. `kindIs "invalid"` is a nil check, and it is the idiom
     pleme-lib already uses in _deployment.tpl and _scaletozero.tpl.
     Args: (list <value> <fallback>) */}}
{{- define "pleme-lib.scrapeTriad.num" -}}
{{- $v := index . 0 -}}
{{- if kindIs "invalid" $v -}}{{- index . 1 -}}{{- else -}}{{- $v -}}{{- end -}}
{{- end -}}

{{- define "pleme-lib.scrapeTriad" -}}
{{- $ctx := .ctx -}}
{{- if kindIs "invalid" $ctx -}}
{{- fail "pleme-lib.scrapeTriad: called without a `ctx` — invoke as (dict \"ctx\" .) so the template can resolve fullname/labels/namespace" -}}
{{- end -}}
{{- $t := .triad | default ($ctx.Values.scrapeTriad) | default dict -}}
{{- $who := include "pleme-lib.fullname" $ctx -}}
{{- if $t.enabled -}}

{{- /* ── flavour: closed enum, unknown HARD-FAILS ───────────────────────── */ -}}
{{- $flavour := $t.flavour | default "" -}}
{{- $flavours := list "vm" "prometheus" -}}
{{- if not (has $flavour $flavours) -}}
{{- fail (printf "pleme-lib.scrapeTriad (%s): set scrapeTriad.flavour to one of %s — got %q. This is a fact about the cluster (which metrics-operator CRDs are registered), not a preference, and applying the wrong kind is a hard apply failure that can stall every manifest beside it. It is never allowed to degrade to emitting nothing, because emitting nothing is the outcome that looks deployed and reports healthy." $who (join "|" $flavours) $flavour) -}}
{{- end -}}

{{- /* ── attach arm: closed enum ─────────────────────────────────────────── */ -}}
{{- $attach := $t.attach | default "service" -}}
{{- if not (has $attach (list "service" "pod")) -}}
{{- fail (printf "pleme-lib.scrapeTriad (%s): scrapeTriad.attach must be \"service\" or \"pod\" — got %q. Use \"pod\" for a workload with no Service; a Service-based scrape would select nothing and report no target at all." $who $attach) -}}
{{- end -}}

{{- /* ── the ONE label set, taken from the workload rather than restated ─── */ -}}
{{/* PRESENCE, not `default`. `x | default y` fills any FALSY value, and
     selectorLabels is never empty — so `selector: {}` and `selector: null`
     both fell through to the fallback and the guard below could not fire.
     hasKey distinguishes "not stated" (inherit, correct) from "stated empty"
     (a mistake that must be refused). Same trap this file's own `.num` helper
     documents one screen down. */}}
{{- $sel := dict -}}
{{- if hasKey $t "selector" -}}
{{- $sel = $t.selector | default dict -}}
{{- else -}}
{{- $sel = (include "pleme-lib.selectorLabels" $ctx | fromYaml) -}}
{{- end -}}
{{- if not $sel -}}
{{- fail (printf "pleme-lib.scrapeTriad (%s): scrapeTriad.selector resolved empty. It must be the workload's OWN spec.selector.matchLabels, so the Service, the scrape and the netpol hole cannot drift apart from the pods." $who) -}}
{{- end -}}

{{- /* ── the ONE port number ─────────────────────────────────────────────── */ -}}
{{- $port := include "pleme-lib.scrapeTriad.num" (list $t.port 0) | int -}}
{{- if le $port 0 -}}
{{- fail (printf "pleme-lib.scrapeTriad (%s): set scrapeTriad.port to the port number the POD listens on. It is used for the Service port, the Service targetPort and the NetworkPolicy hole at once — a NetworkPolicy port is evaluated at the pod, so a second, remapped number here is exactly the pair that is free to disagree." $who) -}}
{{- end -}}
{{- $portName := $t.portName | default "metrics" -}}
{{- $path := $t.path | default "/metrics" -}}

{{- /* ── the two periods, and the Nyquist gate between them ──────────────── */ -}}
{{- $interval := include "pleme-lib.scrapeTriad.num" (list $t.intervalSeconds 0) | int -}}
{{- if le $interval 0 -}}
{{- fail (printf "pleme-lib.scrapeTriad (%s): set scrapeTriad.intervalSeconds (an integer number of seconds). It is declared in seconds rather than as a duration string so the Nyquist gate against scrapeTriad.alertWindowSeconds can actually compare it." $who) -}}
{{- end -}}
{{- $window := include "pleme-lib.scrapeTriad.num" (list $t.alertWindowSeconds 0) | int -}}
{{- if le $window 0 -}}
{{- fail (printf "pleme-lib.scrapeTriad (%s): set scrapeTriad.alertWindowSeconds to the SHORTEST alert evaluation window these series feed. It is required so that \"what is this scrape for\" is answered before the scrape exists — a scrape no rule consumes is a cost, not a signal." $who) -}}
{{- end -}}
{{- if gt (int (mul $interval 2)) $window -}}
{{- fail (printf "pleme-lib.scrapeTriad (%s): scrapeTriad.intervalSeconds=%d cannot feed scrapeTriad.alertWindowSeconds=%d — an alert over a window of W asks about a signal of period W, and fewer than two samples inside W cannot express it, so the rule fires on aliasing or never fires while still reading as correct. Lower intervalSeconds to %d or below, or raise alertWindowSeconds to %d or above." $who $interval $window (div $window 2) (int (mul $interval 2))) -}}
{{- end -}}
{{- $timeout := include "pleme-lib.scrapeTriad.num" (list $t.scrapeTimeoutSeconds 10) | int -}}
{{- if ge $timeout $interval -}}
{{- fail (printf "pleme-lib.scrapeTriad (%s): scrapeTriad.scrapeTimeoutSeconds=%d must be strictly less than scrapeTriad.intervalSeconds=%d — a timeout that reaches the next scrape lets requests overlap on a target that is already slow, which turns a slow endpoint into a missing one." $who $timeout $interval) -}}
{{- end -}}

{{- /* ── who is allowed to scrape: required, and empty is a defect BOTH ways ─ */ -}}
{{- $scrapers := $t.scraperNamespaces | default (list) -}}
{{- if not $scrapers -}}
{{- fail (printf "pleme-lib.scrapeTriad (%s): set scrapeTriad.scraperNamespaces to the namespace(s) your scraper runs in. It has no default on purpose: an empty namespaceSelector matches EVERY namespace (handing the whole cluster a read of this workload's telemetry) and a selector built from an empty name matches none (the blackhole this template exists to prevent) — so the empty case refuses instead of guessing." $who) -}}
{{- end -}}

{{- $ns := include "pleme-lib.namespace" $ctx -}}
{{- $base := include "pleme-lib.labels" $ctx | fromYaml -}}
{{- /* the workload's own labels WIN over the chart's, since they are what makes
       the Service selectable by the scrape CR */ -}}
{{- $svcLabels := merge (deepCopy $sel) (deepCopy $base) -}}
{{- $svcName := $t.serviceName | default (printf "%s-metrics" $who) -}}
{{/* NOT `$who`: the pre-existing `pleme-lib.vmServiceScrape` also defaults its
     CR name to fullname, so a chart composing BOTH emitted two scrape CRs with
     the same (kind, namespace, name) — the second silently overwrites the first
     on apply and one leg of the triad is gone. The `-metrics` suffix matches
     the Service name this template already derives, so the triad's three
     objects read as one set. */}}
{{- $crName := $t.name | default (printf "%s-metrics" $who) -}}
{{- $polName := $t.policyName | default (printf "%s-allow-metrics-scrape" $who) -}}

{{- if eq $attach "service" }}
---
# Leg 1 of 3 — the Service. Without it there are no Endpoints, so the scrape CR
# below selects nothing, so no target is ever created and there is no `up` series
# to be 0. The metrics are served and discarded in the same breath.
apiVersion: v1
kind: Service
metadata:
  name: {{ $svcName }}
  namespace: {{ $ns }}
  labels:
    {{- toYaml $svcLabels | nindent 4 }}
spec:
  {{- if $t.headless }}
  clusterIP: None
  {{- else }}
  type: ClusterIP
  {{- end }}
  selector:
    {{- toYaml $sel | nindent 4 }}
  ports:
    - name: {{ $portName }}
      port: {{ $port }}
      # numeric, single-sourced with the netpol hole below — see the header
      targetPort: {{ $port }}
      protocol: TCP
{{- end }}
---
# Leg 2 of 3 — the scrape CR, in the flavour this cluster's CRDs actually
# register. Its selector is the workload's own matchLabels, not a second copy.
{{- if eq $flavour "vm" }}
apiVersion: operator.victoriametrics.com/v1beta1
kind: {{ if eq $attach "pod" }}VMPodScrape{{ else }}VMServiceScrape{{ end }}
{{- else }}
apiVersion: monitoring.coreos.com/v1
kind: {{ if eq $attach "pod" }}PodMonitor{{ else }}ServiceMonitor{{ end }}
{{- end }}
metadata:
  name: {{ $crName }}
  namespace: {{ $ns }}
  labels:
    {{- toYaml $base | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- toYaml $sel | nindent 6 }}
  {{- if eq $attach "pod" }}
  podMetricsEndpoints:
  {{- else }}
  endpoints:
  {{- end }}
    - port: {{ $portName }}
      path: {{ $path }}
      interval: {{ $interval }}s
      scrapeTimeout: {{ $timeout }}s
---
# Leg 3 of 3 — the port-scoped hole. Without it the target IS created, the
# scraper's connection is refused, and the scrape reports THE TARGET as down
# rather than naming the policy — so the workload takes the blame for a
# firewall. NetworkPolicy ingress is a UNION, so this adds to whatever
# default-deny the namespace already carries and subtracts from nothing.
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ $polName }}
  namespace: {{ $ns }}
  labels:
    {{- toYaml $base | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- toYaml $sel | nindent 6 }}
  policyTypes:
    - Ingress
  ingress:
    - from:
        {{- range $scrapers }}
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ . }}
        {{- end }}
      ports:
        - protocol: TCP
          port: {{ $port }}
{{- end -}}
{{- end -}}
