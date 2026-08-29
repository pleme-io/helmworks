{{/*
pleme-lib: networkpolicy — the deny-all base plus NAMED HOLES

EXTENDS, does not replace. The deny-all + allow-dns + allow-tls-egress trio at
fedramp-moderate+ is owned by _compliance_network.tpl; the toService /
toUpstream egress shapes are owned by _compliance_egress.tpl; the air-gap
shapes by _compliance_airgap.tpl. This file COMPOSES those three and adds the
holes they have no shape for — an apiserver-reachable webhook, a peer derived
from the consumer's declared topology, an explicitly-declared unpoliced
namespace, and a first-enforcement burn-in. There is exactly ONE deny-all
generator in this library and it is NOT here.

WHAT THIS LIBRARY DOES NOT SHIP: a list of workloads, namespaces or tiers. The
allow-set is DERIVED from what the consumer declares in its own values; the
membership is the consumer's, the mechanism is ours. A default that enumerated
real peers would be an architecture diagram with a values key in front of it.

────────────────────────────────────────────────────────────────────────────
THE FOUR TRAPS THIS ENCODES. Each was paid for on a production cluster; the
guards exist because the failure is SILENT in every one of them.

(1) ABSENCE IS NOT DENIAL. Kubernetes NetworkPolicy is default-ALLOW: a
    namespace with no policy and a namespace whose policy was deleted, never
    rendered, or shadowed by an older vendored copy of this library are
    indistinguishable from the outside — all three permit everything, and
    `kubectl get netpol` shows the same empty list for a deliberate decision
    and for an accident. `unpoliced: true` therefore emits an EXPLICIT
    allow-all object carrying its reason, rather than emitting nothing. The
    posture becomes a thing you can read, diff and audit.

(2) A POLICY THAT EXISTS IS NOT A POLICY THAT IS ENFORCED. Measured on one
    production cluster, 2026-07: dozens of default-deny objects across every
    namespace were live, correct, and complete no-ops, because the CNI's
    network-policy feature flag was off. The claim that they were enforced had
    been inferred from two facts that were both TRUE and both insufficient —
    an enforcement-mode env var on the CNI daemonset, and a running policy-agent
    container. The env var is inert while the agent's own flag is off. The only
    honest check is at the agent's flag plus a count of the CNI's DERIVED
    policy objects: policies present and zero derived objects means nothing is
    enforced. A template cannot verify this; it is named here so the next
    author does not re-infer it. Do not treat a rendered NetworkPolicy as a
    security control until that count is non-zero.

(3) TURNING ENFORCEMENT ON IS NOT FREE. Latent denies do not fire gradually —
    flipping the CNI flag with N default-denies already applied enforces all of
    them at once, and every flow they fail to allow breaks in the same second.
    There is no ordering trick that stages this: a pod becomes isolated the
    moment ANY policy selects it, so applying the allow rules "first" already
    switches enforcement on for those pods. The only real staging mechanism is
    an explicit allow-all companion held for a burn-in window while the flows
    are observed — which is what `burnIn` emits. `burnIn.until` is required so
    the window is a decision with an end, not a permanent hole nobody
    remembers. Expiry is NOT enforced here: a fail() that trips on a date
    nobody chose makes the chart un-renderable in CI on a random morning, so
    the expiry belongs to a reconciler that runs continuously, not to a
    template that renders once. Tier-honest: `until` is a stamped commitment,
    not a gate.

(4) ALLOW RULES ARE PURELY ADDITIVE, AND OMISSION WIDENS. Every policy
    selecting a pod is UNIONed; a new, narrower policy never retroactively
    narrows what an existing one already permits — you cannot tighten by
    adding, only by editing what is already there. In the same direction, an
    ingress rule with no `from` peer allows every source, and a rule with no
    `ports` allows every port. Both are the YAML you get by forgetting a field,
    and both render green. So a derived allow entry must name a peer and must
    either name ports or say `allPorts: true` out loud.

────────────────────────────────────────────────────────────────────────────
THE WEBHOOK HOLE, STATED HONESTLY RATHER THAN DRESSED UP.

An admission or conversion webhook is called by the API server itself, and the
API server is not a pod: it has no namespace and no pod labels, so no
`podSelector` or `namespaceSelector` can name it. `ipBlock` is the only peer
type left, which makes `webhookIngress` a raw CIDR hole. There is no cleaner
option, and pretending otherwise by writing a selector that looks precise and
matches nothing is worse than the CIDR.

It gets coarser still where the CNI hands pods real, directly-routable
addresses out of the same subnets the API server's own endpoints sit in — there
the narrowest CIDR containing the API server also contains ordinary pods, so
the hole is "anything in that range", not "the control plane". Excluding the
range to close it would also cut every controller off from the API server,
which trades a scoped exposure for a cluster-wide outage. Two consequences the
consumer owns, not this template:
  * scope the hole to the exact port the webhook serves and nothing else —
    hence `ports` is required, with no default;
  * only open it for an endpoint that is not a credential path and not a
    mutation path into another workload. A validating webhook for a CRD's own
    shape qualifies. A controller's reconcile path does not.
The alternative — no hole at all — fails every admission the webhook governs
the instant the policy reconciles, cluster-wide if its failurePolicy is Fail.
That is the trade; it is not a bug in this template.

DEFENSE IN DEPTH RUNS ONE WAY. A connection needs BOTH the source's egress and
the destination's ingress to allow it. Where the two disagree the DESTINATION's
ingress is the real enforcement point, because it matches on the source pod's
actual namespace identity rather than on an IP heuristic that a shared CIDR
defeats. Put the rule that must hold on the sensitive side; treat the egress
side as depth, and say so rather than claiming egress is restricted.

NO POLICY HERE CAN NAME A HOSTNAME. Plain NetworkPolicy has no FQDN peer: an
external destination is open wide or closed wide, per port. A values key
promising "egress only to this vendor" cannot be honored by this API, so this
template does not offer one.

`scope` PICKS WHOSE PODS. Default `workload` selects only this chart's own pods
(matching every other pleme-lib template). `namespace` emits `podSelector: {}`,
which reaches every pod in the namespace INCLUDING co-tenants this chart does
not own — correct for a namespace-wide baseline, a silent outage for a
neighbour if the namespace is shared. Choose it deliberately.

VERSIONED ALIAS. `pleme-lib.networkpolicy.v1` is the same body under a name no
older vendored copy of this library defines. Helm's named-template namespace is
global and flat, so `pleme-lib.networkpolicy` resolves to whichever copy is
parsed last — and an older copy renders the old shape, silently, exit 0, with
every guard below absent. Call `.v1` when you need the guards to be the ones
that ran.

VALUES (all under .Values.networkPolicy, falling back to .Values.global.networkPolicy):
  enabled            bool   — render the policed shape (chart default true)
  scope              string — workload (default) | namespace
  unpoliced          bool   — declare the workload/namespace deliberately open
  unpolicedReason    string — REQUIRED when unpoliced
  requireDeclaration bool   — turn "neither enabled nor unpoliced" into a fail
  allowDns / allowPrometheus / prometheusNamespaces / allowEgressHttps  (as before)
  additionalIngress[] / additionalEgress[]  { name, rules }  (as before, raw)
  allow.ingress[] / allow.egress[]  — the DERIVED allow-set:
      name       string — REQUIRED, names the emitted object
      namespace  string — peer namespace by kubernetes.io/metadata.name
      podLabels  map    — peer pod labels; WITH namespace this is AND, not OR
      cidr       string — raw peer; mutually exclusive with namespace/podLabels
      except[]   list   — only with cidr
      ports[]    list   — REQUIRED unless allPorts; scalar or {port,protocol}
      allPorts   bool   — say "every port" out loud
  webhookIngress.cidr   string — REQUIRED when the block is present
  webhookIngress.ports  list   — REQUIRED when the block is present
  webhookIngress.port   scalar — one-port shorthand; not alongside ports
  burnIn.enabled bool / burnIn.until string (REQUIRED) / burnIn.reason string (REQUIRED)
*/}}

{{/*
Resolve the networkPolicy values block once. Same fallback order the rest of
this file and its callers already use.
*/}}
{{- define "pleme-lib.networkpolicy.values" -}}
{{- $g := .Values.global | default dict -}}
{{- .Values.networkPolicy | default $g.networkPolicy | default dict | toYaml -}}
{{- end }}

{{/*
Scope-aware podSelector fragment. Emitted at column 0; call with nindent 2
directly under `spec:`.
*/}}
{{- define "pleme-lib.networkpolicy.podSelector" -}}
{{- $np := (include "pleme-lib.networkpolicy.values" . | fromYaml) -}}
{{- if eq ($np.scope | default "workload") "namespace" -}}
podSelector: {}
{{- else -}}
podSelector:
  matchLabels:
    {{- include "pleme-lib.selectorLabels" . | nindent 4 }}
{{- end -}}
{{- end }}

{{/*
Port list fragment. Accepts scalars (TCP assumed) or { port, protocol } maps.
Emitted at column 0; call with nindent 8 under a `ports:` key at column 6.
*/}}
{{- define "pleme-lib.networkpolicy.ports" -}}
{{- range . }}
{{- if kindIs "map" . }}
- port: {{ .port }}
  protocol: {{ .protocol | default "TCP" }}
{{- else }}
- port: {{ . }}
  protocol: TCP
{{- end }}
{{- end }}
{{- end }}

{{/*
One peer as a YAML list item. Emitted at column 0; call with nindent 8 under a
`from:`/`to:` key at column 6.

namespaceSelector and podSelector inside ONE peer element are ANDed (pods with
those labels IN that namespace). Two separate elements are ORed. A rule meant
to allow "everything in namespace A, plus anything labelled B" written as one
element allows neither — declare two entries.
*/}}
{{- define "pleme-lib.networkpolicy.peer" -}}
{{- if .cidr }}
- ipBlock:
    cidr: {{ .cidr }}
{{- with .except }}
    except:
{{- toYaml . | nindent 6 }}
{{- end }}
{{- else if .namespace }}
- namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: {{ .namespace }}
{{- with .podLabels }}
  podSelector:
    matchLabels:
{{- toYaml . | nindent 6 }}
{{- end }}
{{- else }}
- podSelector:
    matchLabels:
{{- toYaml .podLabels | nindent 6 }}
{{- end }}
{{- end }}

{{/*
Every refusal, in one place, so a caller cannot render half a posture. Each
message names the values key that fixes it.
*/}}
{{- define "pleme-lib.networkpolicy.validate" -}}
{{- $np := (include "pleme-lib.networkpolicy.values" . | fromYaml) -}}
{{- $unpoliced := eq (toString ($np.unpoliced | default false)) "true" -}}
{{- $enabled := eq (toString ($np.enabled | default false)) "true" -}}
{{- $scope := $np.scope | default "workload" -}}
{{- if not (has $scope (list "workload" "namespace")) -}}
  {{- fail (printf "networkPolicy.scope is %q; set it to \"workload\" (this chart's pods) or \"namespace\" (every pod in the namespace, co-tenants included)" $scope) -}}
{{- end -}}
{{- if and $unpoliced $enabled -}}
  {{- fail "networkPolicy declares both unpoliced=true and enabled=true — a deny-all and a deliberate allow-all cannot both be the posture; set networkPolicy.unpoliced=false to police it, or networkPolicy.enabled=false to leave it open" -}}
{{- end -}}
{{- if $unpoliced -}}
  {{- if not $np.unpolicedReason -}}
    {{- fail "networkPolicy.unpoliced=true requires networkPolicy.unpolicedReason — an unpoliced namespace is a decision and must carry the reason it was made, because k8s is default-allow and an unexplained open namespace is indistinguishable from a forgotten one" -}}
  {{- end -}}
  {{- if eq (include "pleme-lib.compliance.network.required" .) "true" -}}
    {{- fail "networkPolicy.unpoliced=true is forbidden at this compliance.baseline, which mandates NetworkPolicy enforcement (AC-4, SC-7); lower compliance.baseline or police the workload" -}}
  {{- end -}}
{{- end -}}
{{- if and (eq (toString ($np.requireDeclaration | default false)) "true") (not $unpoliced) (not $enabled) -}}
  {{- fail "networkPolicy.requireDeclaration=true and the posture is undeclared: set networkPolicy.enabled=true to police, or networkPolicy.unpoliced=true with networkPolicy.unpolicedReason to state it is deliberately open. Rendering nothing is not the third option — k8s is default-allow, so silence and an intentional allow-all look identical in the cluster" -}}
{{- end -}}
{{- $wh := $np.webhookIngress | default dict -}}
{{- if $wh -}}
  {{- if and $wh.port $wh.ports -}}
    {{- fail "networkPolicy.webhookIngress sets both port and ports — pick one; ports is the list form, port is the single-port shorthand" -}}
  {{- end -}}
  {{- $whPorts := $wh.ports | default (ternary (list $wh.port) (list) (hasKey $wh "port")) -}}
  {{- if not $wh.cidr -}}
    {{- fail "networkPolicy.webhookIngress requires networkPolicy.webhookIngress.cidr — the API server calling your webhook is not a pod, so no podSelector or namespaceSelector can name it and ipBlock is the only peer type left; this library ships no default address" -}}
  {{- end -}}
  {{- if not $whPorts -}}
    {{- fail "networkPolicy.webhookIngress requires networkPolicy.webhookIngress.ports (or .port) — a CIDR hole with no port allows that range to every port this workload listens on, which is the widening this knob exists to avoid" -}}
  {{- end -}}
{{- end -}}
{{- $burn := $np.burnIn | default dict -}}
{{- if eq (toString ($burn.enabled | default false)) "true" -}}
  {{- if not $burn.until -}}
    {{- fail "networkPolicy.burnIn.enabled=true requires networkPolicy.burnIn.until — a burn-in allow-all with no end date is a permanent hole that renders as a temporary one" -}}
  {{- end -}}
  {{- if not $burn.reason -}}
    {{- fail "networkPolicy.burnIn.enabled=true requires networkPolicy.burnIn.reason — the next reader must be able to tell a staged first enforcement from an abandoned one" -}}
  {{- end -}}
{{- end -}}
{{- $allow := $np.allow | default dict -}}
{{- range $dir := list "ingress" "egress" -}}
{{- range $i, $rule := (index $allow $dir | default list) -}}
  {{- if not $rule.name -}}
    {{- fail (printf "networkPolicy.allow.%s[%d].name is required — it names the emitted NetworkPolicy, and two unnamed entries would collide into one object" $dir $i) -}}
  {{- end -}}
  {{- if and $rule.cidr (or $rule.namespace $rule.podLabels) -}}
    {{- fail (printf "networkPolicy.allow.%s[%d] (%s) sets cidr alongside namespace/podLabels — the API rejects ipBlock combined with a selector in one peer; split it into two entries" $dir $i $rule.name) -}}
  {{- end -}}
  {{- if and $rule.except (not $rule.cidr) -}}
    {{- fail (printf "networkPolicy.allow.%s[%d] (%s) sets except without cidr — except is only meaningful inside an ipBlock" $dir $i $rule.name) -}}
  {{- end -}}
  {{- if not (or $rule.cidr $rule.namespace $rule.podLabels) -}}
    {{- fail (printf "networkPolicy.allow.%s[%d] (%s) names no peer — set namespace, podLabels or cidr. A rule with no peer does not allow nothing, it allows EVERY source, which is the silent widening this guard exists to catch" $dir $i $rule.name) -}}
  {{- end -}}
  {{- if and (not $rule.ports) (ne (toString ($rule.allPorts | default false)) "true") -}}
    {{- fail (printf "networkPolicy.allow.%s[%d] (%s) names no ports — set ports, or say allPorts=true out loud. An omitted port list allows every port, so forgetting the field and meaning it render identically" $dir $i $rule.name) -}}
  {{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
The explicit "deliberately unpoliced" declaration.

Emits an allow-all rather than emitting nothing, so the decision exists as an
object with a reason on it. Sound because allow rules are additive: an
allow-all selecting these pods wins over any deny-all that also selects them.
*/}}
{{- define "pleme-lib.networkpolicy.unpoliced" -}}
{{- $np := (include "pleme-lib.networkpolicy.values" . | fromYaml) -}}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-unpoliced
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    pleme.io/netpol-posture: "unpoliced"
    pleme.io/netpol-unpoliced-reason: {{ $np.unpolicedReason | quote }}
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" . | nindent 2 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - {}
  egress:
    - {}
{{- end }}

{{/*
The first-enforcement burn-in companion. See trap (3): there is no ordering
that stages enforcement, so the only honest stager is an explicit allow-all
held beside the real policies while the flows are watched. Delete the block to
finish the rollout — the deny-all underneath is already in place and starts
biting the moment this object goes away.
*/}}
{{- define "pleme-lib.networkpolicy.burnIn" -}}
{{- $np := (include "pleme-lib.networkpolicy.values" . | fromYaml) -}}
{{- $burn := $np.burnIn | default dict -}}
{{- if eq (toString ($burn.enabled | default false)) "true" }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-burn-in-allow-all
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    pleme.io/netpol-posture: "burn-in"
    pleme.io/netpol-burn-in-until: {{ $burn.until | quote }}
    pleme.io/netpol-burn-in-reason: {{ $burn.reason | quote }}
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" . | nindent 2 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - {}
  egress:
    - {}
{{- end }}
{{- end }}

{{/*
The apiserver-reachable webhook hole. A raw CIDR by necessity, scoped to the
declared ports and nothing else. See the header for why no selector can do
this and what the coarseness costs.
*/}}
{{- define "pleme-lib.networkpolicy.webhookIngress" -}}
{{- $np := (include "pleme-lib.networkpolicy.values" . | fromYaml) -}}
{{- $wh := $np.webhookIngress | default dict -}}
{{- if $wh }}
{{- $whPorts := $wh.ports | default (ternary (list $wh.port) (list) (hasKey $wh "port")) }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-apiserver-webhook
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    pleme.io/netpol-hole: "apiserver-webhook"
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" . | nindent 2 }}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - ipBlock:
            cidr: {{ $wh.cidr }}
      ports:
        {{- include "pleme-lib.networkpolicy.ports" $whPorts | trim | nindent 8 }}
{{- end }}
{{- end }}

{{/*
The derived allow-set: one NetworkPolicy per declared peer, ingress and egress.
Derived from the consumer's own topology declaration — this library supplies
the shape and the refusals, never the membership.
*/}}
{{- define "pleme-lib.networkpolicy.derivedAllow" -}}
{{- $np := (include "pleme-lib.networkpolicy.values" . | fromYaml) -}}
{{- $allow := $np.allow | default dict -}}
{{- range $allow.ingress }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" $ }}-allow-in-{{ .name }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" $ | nindent 2 }}
  policyTypes:
    - Ingress
  ingress:
    - from:
        {{- include "pleme-lib.networkpolicy.peer" . | trim | nindent 8 }}
      {{- if .ports }}
      ports:
        {{- include "pleme-lib.networkpolicy.ports" .ports | trim | nindent 8 }}
      {{- end }}
{{- end }}
{{- range $allow.egress }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" $ }}-allow-out-{{ .name }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" $ | nindent 2 }}
  policyTypes:
    - Egress
  egress:
    - to:
        {{- include "pleme-lib.networkpolicy.peer" . | trim | nindent 8 }}
      {{- if .ports }}
      ports:
        {{- include "pleme-lib.networkpolicy.ports" .ports | trim | nindent 8 }}
      {{- end }}
{{- end }}
{{- end }}

{{/*
The consumer's raw escape hatch, unchanged. Rules are passed through verbatim,
so nothing here can guard them — prefer allow.ingress/allow.egress, which are
validated.
*/}}
{{- define "pleme-lib.networkpolicy.additional" -}}
{{- $np := (include "pleme-lib.networkpolicy.values" . | fromYaml) -}}
{{- range $np.additionalIngress }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" $ }}-{{ .name }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" $ | nindent 2 }}
  policyTypes:
    - Ingress
  ingress:
    {{- toYaml .rules | nindent 4 }}
{{- end }}
{{- range $np.additionalEgress }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" $ }}-{{ .name }}
  namespace: {{ include "pleme-lib.namespace" $ }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" $ | nindent 2 }}
  policyTypes:
    - Egress
  egress:
    {{- toYaml .rules | nindent 4 }}
{{- end }}
{{- end }}

{{/*
Entry point. Three postures, and exactly three:

  compliance-required — _compliance_network.tpl owns the deny-all trio,
                        _compliance_egress.tpl and _compliance_airgap.tpl own
                        the egress shapes; the holes below are layered on top.
  policed             — this chart's own deny-all base plus the named holes.
  unpoliced           — an explicit, annotated allow-all (never silence).

Rendering nothing is not a posture. It is the state the guards above exist to
make impossible to reach by accident.
*/}}
{{- define "pleme-lib.networkpolicy.v1" -}}
{{- include "pleme-lib.networkpolicy.validate" . -}}
{{- $np := (include "pleme-lib.networkpolicy.values" . | fromYaml) -}}
{{- $complianceRequired := include "pleme-lib.compliance.network.required" . -}}
{{- if eq $complianceRequired "true" -}}
{{ include "pleme-lib.compliance.network.policies" . }}
{{- /* Layer 1: generic egress shapes (toService / toUpstream) */ -}}
{{ include "pleme-lib.compliance.egress.policies" . }}
{{- /* Layer 2: air-gap shapes (consumer / registry-mirror) */ -}}
{{ include "pleme-lib.compliance.airgap.policies" . }}
{{- /* Layer 3: the named holes this file owns */ -}}
{{ include "pleme-lib.networkpolicy.webhookIngress" . }}
{{ include "pleme-lib.networkpolicy.derivedAllow" . }}
{{ include "pleme-lib.networkpolicy.burnIn" . }}
{{ include "pleme-lib.networkpolicy.additional" . }}
{{- else if eq (toString ($np.unpoliced | default false)) "true" -}}
{{ include "pleme-lib.networkpolicy.unpoliced" . }}
{{- else if $np.enabled }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-deny-all
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  annotations:
    pleme.io/netpol-posture: "policed"
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" . | nindent 2 }}
  policyTypes:
    - Ingress
    - Egress
{{- if $np.allowDns }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-dns
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" . | nindent 2 }}
  policyTypes:
    - Egress
  egress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
{{- end }}
{{- if $np.allowPrometheus }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-prometheus
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" . | nindent 2 }}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: prometheus-operator
        {{- range $np.prometheusNamespaces }}
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: {{ . }}
        {{- end }}
      ports:
        - port: {{ (.Values.monitoring).port | default "http" }}
          protocol: TCP
{{- end }}
{{- /*
  allowEgressHttps — "talks to public API" shape that doesn't fit
  compliance.egress.toUpstream's allowlist model. Emits one
  NetworkPolicy allowing TCP 443 egress to 0.0.0.0/0 except RFC1918 +
  link-local ranges. Use for charts that egress to public-internet APIs
  without enumerating the upstream CIDRs — which plain NetworkPolicy
  cannot do by hostname at all (see the header's FQDN note).

  At fedramp-moderate+ baseline, prefer compliance.egress.toUpstream
  with a curated allowedCidrs list (auditable, principle-of-least-
  privilege). This helper is the not-yet-curated path.
*/}}
{{- if $np.allowEgressHttps }}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "pleme-lib.fullname" . }}-allow-egress-https
  namespace: {{ include "pleme-lib.namespace" . }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
spec:
  {{- include "pleme-lib.networkpolicy.podSelector" . | nindent 2 }}
  policyTypes:
    - Egress
  egress:
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8
              - 172.16.0.0/12
              - 192.168.0.0/16
              - 169.254.0.0/16
      ports:
        - protocol: TCP
          port: 443
{{- end }}
{{ include "pleme-lib.networkpolicy.webhookIngress" . }}
{{ include "pleme-lib.networkpolicy.derivedAllow" . }}
{{ include "pleme-lib.networkpolicy.burnIn" . }}
{{ include "pleme-lib.networkpolicy.additional" . }}
{{- end }}
{{- end }}

{{/*
Back-compat name. The BODY lives in `pleme-lib.networkpolicy.v1` and this is the
thin wrapper — that direction is load-bearing and was wrong the other way round.

Helm's template namespace is FLAT across a chart and its vendored dependency
copies, and the shallowest parse wins. `pleme-lib.networkpolicy` is a
pre-existing name every vendored copy defines, so a `.v1` that merely *called*
it dispatched into whichever copy won — proven in a scratch chart with a shallow
stale copy: `.v1` rendered exit 0 on values these guards must refuse, bypassing
all fifteen. A suffixed alias only shadow-proofs anything if it OWNS the body.

This matches `_scaletozero.tpl`'s precedent in this same directory, which puts
the real body in `.v1` and defines no un-suffixed name at all.
*/}}
{{- define "pleme-lib.networkpolicy" -}}
{{ include "pleme-lib.networkpolicy.v1" . }}
{{- end }}
