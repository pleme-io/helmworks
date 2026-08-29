{{/*
pleme-lib.flux — GitOps plumbing as a declared shape: sources, an ordered
layer DAG, and HelmRelease defaults that survive a bad day.

WHAT THIS OWNS. Three objects that always ship together and are always
hand-written together, so they always drift apart: the SOURCE a reconciler
pulls from, the ORDERED LAYERS it applies, and the HelmRelease IDIOM that
decides what happens when one of them is unhealthy. Written by hand they agree
on the day they are written and never again.

WHAT THIS DELIBERATELY DOES NOT OWN. The membership of a layer. `flux.layers`
has NO DEFAULT and never will: a default layer list is an architecture diagram
shipped inside a library, correct for exactly one cluster and quietly wrong for
every other. The library owns the VERB (emit a Kustomization), the ORDER (edge
i depends on edge i-1), the RULE (an edge must name a layer that exists) and
the GATE (refuse what cannot converge). Membership is the consumer's.

════════════════════════════════════════════════════════════════════════════
FOUR LAWS. Each one cost a real outage somewhere; each is silent.
════════════════════════════════════════════════════════════════════════════

  1. NEVER REPUBLISH AN EXISTING VERSION. Pushing new bytes under a version
     that already exists is skipped silently and the OLD BYTES STAY LIVE.
     A reconciler that already resolved that exact pin treats it as immutable
     per OCI convention -- it does not re-diff digests on its interval, only
     when the CONSTRAINT would match a different tag. Measured on one cluster,
     2026-07: the controller reported UpgradeSucceeded for a full day (true --
     it correctly applied the chart it had) while the live CRD stayed frozen at
     its pre-fix shape and `metadata.generation` never incremented. A fresh
     pull of that same tag returned a DIFFERENT digest than the cached one.
     Both sides green, contents divergent, nothing to look at. Cut a new
     version even for a same-day fix. A mutable tag is `:latest` renamed.

  2. A WRONG CREDENTIAL IS WORSE THAN NONE. A registry credential is attached
     to EVERY request, so a dead one makes the ANONYMOUS path fail too: a
     public artifact that any stranger can pull returns 401 to the one client
     holding a rejected token. That is why a credential outage reads as a cache
     or network fault and gets diagnosed for days -- measured on one cluster,
     2026-08: a source sat broken for four days because the failure looked
     nothing like an auth failure. A public source therefore declares
     `public: true` and carries NO secretRef, and this template refuses the
     combination rather than letting one dead token break the path that needed
     no token at all.

  3. A GENERATED FILE IS NOT EDITABLE. The sync objects a bootstrap command
     writes are regenerated WHOLESALE on the next bootstrap or controller
     upgrade, so a hand-edit to them is reverted with no error and no diff to
     notice. Express the change where it survives: a kustomize patch beside
     the generated file, or the source this template renders from. This
     template refuses to emit a source that collides with the bootstrap-
     generated one unless the collision is declared, because two producers of
     one object is a fight that the generated side always wins.

  4. `ssh.github.com:443` WHEN PORT 22 IS CLOSED. Many clusters have no egress
     on 22, and a clone against `github.com:22` does not fail fast -- it hangs
     to a TCP timeout, which reads as a slow network rather than a closed port.
     GitHub serves the identical SSH endpoint on 443 at `ssh.github.com` for
     exactly this case. Same key, same host keys; only the port moves.

════════════════════════════════════════════════════════════════════════════
THE LAYER DAG, and the one thing about it that is NOT symmetric.
════════════════════════════════════════════════════════════════════════════

`dependsOn` is a BRING-UP edge and only a bring-up edge. Order the list so
that the layer granting capacity is Ready before the layers that schedule onto
it, and so that any layer which WRITES to the others -- an autoscaler, a
reconciler, a controller that mutates limits -- comes first in the list and is
therefore unblocked LAST on the way up. Measured on one cluster, 2026-08: an
autoscaler released while the tiers above it were still rolling out began
writing against a half-present fleet.

Teardown runs the list in REVERSE, and no edge expresses that -- removing
layers is top-down, one commit at a time, verifying each rung. A reconciler
will not do it for you and there is no annotation that says so. Bring-up in
one commit is safe because each edge gates the next; teardown in one commit
is not, because nothing gates anything on the way down.

════════════════════════════════════════════════════════════════════════════
disableWait: WHEN A CHART'S READINESS IS NOT ITS WORKLOAD'S READINESS.
════════════════════════════════════════════════════════════════════════════

Helm's default wait blocks the ENTIRE release on ANY resource it considers
stalled. For a multi-service release with one already-unhealthy member that is
a genuine deadlock, not a delay: the fix for service X can never land, because
unrelated already-broken service Y trips the abort first. Measured on one
cluster, 2026-07: five consecutive upgrades each aborted on a DIFFERENT
pre-existing failure before reaching the resource the change was fixing.

`disableWait` applies every resource's spec unconditionally and lets pods
converge against the corrected spec. It also throws away the readiness signal,
which is why `flux.release.disableWaitReason` is REQUIRED: an unexplained
disableWait gets copy-pasted onto releases whose readiness genuinely is their
workload's readiness, and those releases then report Ready before they are.

════════════════════════════════════════════════════════════════════════════
bootstrap.staged: land the artifact complete, BEFORE it reconciles.
════════════════════════════════════════════════════════════════════════════

Three independent brakes, so that removing any ONE of them by hand still does
not make the artifact live:

  suspended          the reconciler sees the object and does nothing
  prune-scoped       prune off + the prune-disabled annotation, so a suspended
                     object can never garbage-collect what it does not manage
  an unresolved pin  an exact digest (or an exact, range-free version) naming
                     bytes that need not be published yet -- so even an
                     un-suspended release cannot pull "whatever is there now"

This is how a complete, reviewed artifact lands in git ahead of the thing it
needs, instead of arriving as a half-file with a TODO. Both `blockedBy` and
`clearedBy` are required: a staged artifact with no stated clearing condition
is indistinguishable from one somebody forgot.

USAGE

  templates/flux.yaml:
    {{- include "pleme-lib.flux" . }}

  or piecewise:
    {{- include "pleme-lib.flux.sources" . }}
    {{- include "pleme-lib.flux.layers" . }}
    {{- include "pleme-lib.flux.release" . }}

VALUES

  flux:
    enabled: true
    namespace: flux-system            # where sources + Kustomizations land

    sources:                          # [] is fine; the consumer may bring its own
      - name: charts
        kind: HelmRepository          # HelmRepository | OCIRepository | GitRepository
        url: oci://<registry>/<org>/charts
        type: oci                     # HelmRepository only: oci | default
        interval: 10m
        secretRef: <pull-secret>      # omit entirely for a public source
        public: false                 # true => secretRef is REFUSED (law 2)
        adoptBootstrap: false         # true => may collide with a generated name
        ref:                          # Git/OCI: exactly one of these
          branch: main
          tag: ""
          semver: ""
          digest: ""
        ignore: |                     # Git only
          /*
          !/charts/

    layers:                           # ORDERED. No default -- see above.
      - name: <operator-supplied>
        path: ./<path/in/the/source>
        dependsOn: []                 # omit => the previous layer in the list
        targetNamespace: ""
        wait: true
        patches: []                   # passthrough
    layerDefaults:
      sourceRef: { kind: GitRepository, name: <source> }
      interval: 10m
      timeout: 5m
      prune: true
      decryption: { provider: sops, secretRef: <age-secret> }

    release:
      enabled: false
      name: ""                        # default: pleme-lib.fullname
      targetNamespace: ""
      interval: 30m
      timeout: 10m
      crds: CreateReplace
      retries: 3
      driftDetection: enabled
      createNamespace: false
      disableWait: false
      disableWaitReason: ""           # REQUIRED when disableWait
      dependsOn: []                   # [{name, namespace}]
      chart:
        name: <chart>
        version: <exact-or-range>
        sourceRef: { kind: HelmRepository, name: <source>, namespace: flux-system }
      valuesFrom: []
      values: {}

    bootstrap:
      staged: false
      digest: ""                      # sha256:<64 hex>; required when staged
      blockedBy: ""                   # required when staged
      clearedBy: ""                   # required when staged
      since: ""                       # optional ISO date
*/}}

{{/* Where sources and Kustomizations land. One answer, read by every helper. */}}
{{- define "pleme-lib.flux.namespace" -}}
{{- $f := .Values.flux | default dict -}}
{{- $f.namespace | default "flux-system" -}}
{{- end }}

{{/* Is the staged profile on? Single source of truth for all three brakes. */}}
{{- define "pleme-lib.flux.staged" -}}
{{- $f := .Values.flux | default dict -}}
{{- $b := $f.bootstrap | default dict -}}
{{- if $b.staged -}}true{{- else -}}false{{- end -}}
{{- end }}

{{/*
Why an object is inert, on the object itself. A staged artifact whose reason
lives only in a commit message is one someone un-suspends "because it looks
finished".
*/}}
{{- define "pleme-lib.flux.stagedAnnotations" -}}
{{- $b := (.Values.flux | default dict).bootstrap | default dict -}}
pleme.io/blocked-by: {{ $b.blockedBy | quote }}
pleme.io/blocked-clearing: {{ $b.clearedBy | quote }}
{{- with $b.since }}
pleme.io/blocked-since: {{ . | quote }}
{{- end }}
{{- if $b.digest }}
pleme.io/staged-digest: {{ $b.digest | quote }}
{{- end }}
{{- end }}

{{/*
Refuse what cannot converge, and name the key that fixes it.

Every check below is a state that renders GREEN and reconciles forever without
arriving: a dependency edge onto a name nobody defined reports "dependency not
ready" for eternity and never once says the name is a typo.
*/}}
{{- define "pleme-lib.flux.validate" -}}
{{- $f := .Values.flux | default dict -}}
{{- $b := $f.bootstrap | default dict -}}

{{- /* ── the staged profile ─────────────────────────────────────────────── */}}
{{- if eq (include "pleme-lib.flux.staged" .) "true" -}}
  {{- if not $b.blockedBy -}}
    {{- fail "flux: `flux.bootstrap.blockedBy` is required when `flux.bootstrap.staged` is true -- a staged artifact with no stated blocker is indistinguishable from one somebody forgot to finish, and gets un-suspended because it looks complete" -}}
  {{- end -}}
  {{- if not $b.clearedBy -}}
    {{- fail (printf "flux: `flux.bootstrap.clearedBy` is required when staged (blocked by %q) -- name the condition that makes this safe to reconcile, or nobody can tell whether it is still blocked" $b.blockedBy) -}}
  {{- end -}}
  {{- if not $b.digest -}}
    {{- fail "flux: `flux.bootstrap.digest` is required when `flux.bootstrap.staged` is true -- the third brake is an unresolved pin, so that an artifact un-suspended by hand still cannot pull whatever happens to be published at that moment" -}}
  {{- end -}}
  {{- if not (regexMatch "^sha256:[0-9a-f]{64}$" ($b.digest | toString)) -}}
    {{- fail (printf "flux: `flux.bootstrap.digest` must be an exact `sha256:<64 lowercase hex>` pin, got %q -- a tag or range re-resolves on the next reconcile, which is the mutable-pin failure this profile exists to prevent" $b.digest) -}}
  {{- end -}}
  {{- $v := ((($f.release | default dict).chart) | default dict).version | toString -}}
  {{- if and $v (regexMatch "[x*^~<>]" $v) -}}
    {{- fail (printf "flux: `flux.release.chart.version` is a RANGE (%q) and `flux.bootstrap.staged` is true -- a range re-resolves the moment a matching version is published, so the staged artifact would go live on somebody else's publish rather than on your decision. Pin an exact version" $v) -}}
  {{- end -}}
{{- end -}}

{{- /* ── sources ──────────────────────────────────────────────────────────── */}}
{{- range $i, $s := ($f.sources | default list) -}}
  {{- if not $s.name -}}
    {{- fail (printf "flux: `flux.sources[%d].name` is required -- an unnamed source cannot be referenced by any Kustomization or release" $i) -}}
  {{- end -}}
  {{- if not $s.url -}}
    {{- fail (printf "flux: `flux.sources[%d].url` is required for source %q" $i $s.name) -}}
  {{- end -}}
  {{- $k := $s.kind | default "HelmRepository" -}}
  {{- if not (has $k (list "HelmRepository" "OCIRepository" "GitRepository")) -}}
    {{- fail (printf "flux: `flux.sources[%d].kind` must be one of HelmRepository|OCIRepository|GitRepository, got %q for source %q" $i $k $s.name) -}}
  {{- end -}}
  {{- /* LAW 2 -- a rejected credential breaks the anonymous path too. */ -}}
  {{- if and $s.public $s.secretRef -}}
    {{- fail (printf "flux: source %q sets BOTH `flux.sources[%d].public: true` and `.secretRef` -- a credential is attached to every request, so a rejected one makes even an anonymous read fail with 401 on an artifact any stranger could pull. Drop the secretRef, or drop `public: true` if the source really is private" $s.name $i) -}}
  {{- end -}}
  {{- /* LAW 4 -- port 22 hangs to a timeout and reads as a slow network. */ -}}
  {{- if and (not $s.allowPort22) (regexMatch "^ssh://[^@/]+@github\\.com(:22)?/" ($s.url | toString)) -}}
    {{- fail (printf "flux: `flux.sources[%d].url` for %q uses github.com over SSH port 22. Many clusters have no egress on 22 and the clone HANGS to a TCP timeout rather than failing fast, so it reads as a slow network instead of a closed port. Use ssh://git@ssh.github.com:443/<org>/<repo>.git -- same key, same host keys, only the port moves. Set `.allowPort22: true` if 22 is genuinely open here" $i $s.name) -}}
  {{- end -}}
  {{- if regexMatch "^[A-Za-z0-9._-]+@[A-Za-z0-9._-]+:" ($s.url | toString) -}}
    {{- fail (printf "flux: `flux.sources[%d].url` for %q is an scp-style address; a source URL needs an explicit scheme (ssh:// https:// oci://) or the controller cannot parse it" $i $s.name) -}}
  {{- end -}}
  {{- /* LAW 3 -- two producers of one generated object; the generator wins. */ -}}
  {{- if and (eq $s.name "flux-system") (not $s.adoptBootstrap) -}}
    {{- fail (printf "flux: `flux.sources[%d].name` is \"flux-system\", which collides with the source the bootstrap command GENERATES. That file is rewritten wholesale on the next bootstrap or controller upgrade, so whichever of the two producers you edit by hand loses with no error and no diff. Rename the source, or set `.adoptBootstrap: true` if this chart is deliberately taking ownership" $i) -}}
  {{- end -}}
{{- end -}}

{{- /* ── the layer DAG ────────────────────────────────────────────────────── */}}
{{- $layers := $f.layers | default list -}}
{{- if $layers -}}
  {{- $names := dict -}}
  {{- range $i, $l := $layers -}}
    {{- if not $l.name -}}
      {{- fail (printf "flux: `flux.layers[%d].name` is required -- layer names are operator-supplied and this library ships no default, because a default layer list is an architecture rather than a mechanism" $i) -}}
    {{- end -}}
    {{- if hasKey $names $l.name -}}
      {{- fail (printf "flux: `flux.layers[].name` %q appears twice -- two Kustomizations with one name silently overwrite each other and only the last one applied survives" $l.name) -}}
    {{- end -}}
    {{- if not $l.path -}}
      {{- fail (printf "flux: `flux.layers[%d].path` is required for layer %q -- a Kustomization with no path applies the repository root" $i $l.name) -}}
    {{- end -}}
    {{- $_ := set $names $l.name true -}}
  {{- end -}}
  {{- range $i, $l := $layers -}}
    {{- range $d := ($l.dependsOn | default list) -}}
      {{- $dn := $d.name | default ($d | toString) -}}
      {{- if not (hasKey $names $dn) -}}
        {{- fail (printf "flux: `flux.layers[%d].dependsOn` on layer %q names %q, which is not a declared layer. A dependency edge onto a name nobody defined never resolves: the Kustomization reports `dependency not ready` on every interval, forever, and never once says the name is a typo" $i $l.name $dn) -}}
      {{- end -}}
      {{- if eq $dn $l.name -}}
        {{- fail (printf "flux: layer %q depends on itself (`flux.layers[%d].dependsOn`) -- it can never become Ready" $l.name $i) -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- /* ── the release ──────────────────────────────────────────────────────── */}}
{{- $r := $f.release | default dict -}}
{{- if $r.enabled -}}
  {{- $c := $r.chart | default dict -}}
  {{- if not $c.name -}}
    {{- fail "flux: `flux.release.chart.name` is required when `flux.release.enabled` is true" -}}
  {{- end -}}
  {{- if not ($c.sourceRef | default dict).name -}}
    {{- fail (printf "flux: `flux.release.chart.sourceRef.name` is required for chart %q -- a release with no source has nothing to pull" $c.name) -}}
  {{- end -}}
  {{- if and $r.disableWait (not $r.disableWaitReason) -}}
    {{- fail (printf "flux: `flux.release.disableWaitReason` is required whenever `flux.release.disableWait` is true (chart %q). disableWait throws away the readiness signal -- it is correct only where a chart's readiness is genuinely not its workload's readiness, and an unexplained one gets copy-pasted onto releases that then report Ready before they are" $c.name) -}}
  {{- end -}}
  {{- range $i, $d := ($r.dependsOn | default list) -}}
    {{- if not $d.name -}}
      {{- fail (printf "flux: `flux.release.dependsOn[%d].name` is required" $i) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end }}

{{/*
Sources. A HelmRepository of `type: oci` is a registry namespace, an
OCIRepository is one artifact, a GitRepository is a tree -- and only the last
two carry a `ref`, which is why the digest brake reaches them and not the
first.
*/}}
{{- define "pleme-lib.flux.sources" -}}
{{- include "pleme-lib.flux.validate" . -}}
{{- $f := .Values.flux | default dict -}}
{{- if $f.enabled -}}
{{- $ns := include "pleme-lib.flux.namespace" . -}}
{{- $staged := eq (include "pleme-lib.flux.staged" .) "true" -}}
{{- $b := $f.bootstrap | default dict -}}
{{- range $s := ($f.sources | default list) }}
{{- $kind := $s.kind | default "HelmRepository" }}
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: {{ $kind }}
metadata:
  name: {{ $s.name }}
  namespace: {{ $ns }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
  annotations:
    {{- include "pleme-lib.fluxcdPruneDisabled" $ | nindent 4 }}
    {{- if $staged }}
    {{- include "pleme-lib.flux.stagedAnnotations" $ | nindent 4 }}
    {{- end }}
spec:
  interval: {{ $s.interval | default "10m" }}
  url: {{ $s.url | quote }}
  {{- if and (eq $kind "HelmRepository") $s.type }}
  type: {{ $s.type }}
  {{- end }}
  {{- if ne $kind "HelmRepository" }}
  ref:
    {{- /* The staged digest WINS over any tag or branch: an unresolved pin is
           the brake, and a branch beside it would quietly re-resolve. */}}
    {{- if $staged }}
    digest: {{ $b.digest | quote }}
    {{- else if ($s.ref | default dict).digest }}
    digest: {{ $s.ref.digest | quote }}
    {{- else if ($s.ref | default dict).semver }}
    semver: {{ $s.ref.semver | quote }}
    {{- else if ($s.ref | default dict).tag }}
    tag: {{ $s.ref.tag | quote }}
    {{- else }}
    branch: {{ ($s.ref | default dict).branch | default "main" | quote }}
    {{- end }}
  {{- end }}
  {{- /* LAW 2: emitted ONLY when present. An empty secretRef names a Secret
         that does not exist and fails the source closed. */}}
  {{- with $s.secretRef }}
  secretRef:
    name: {{ . | quote }}
  {{- end }}
  {{- with $s.ignore }}
  ignore: |
    {{- . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
The layer DAG. Edge i -> i-1 is DERIVED from list order, so adding a layer in
the middle re-wires the chain instead of leaving a stale hand-written edge
pointing past it. An explicit `dependsOn` overrides the derived edge for the
genuine fan-in case; it is validated against the declared set above.
*/}}
{{- define "pleme-lib.flux.layers" -}}
{{- include "pleme-lib.flux.validate" . -}}
{{- $f := .Values.flux | default dict -}}
{{- $layers := $f.layers | default list -}}
{{- if and $f.enabled $layers -}}
{{- $ns := include "pleme-lib.flux.namespace" . -}}
{{- $d := $f.layerDefaults | default dict -}}
{{- $staged := eq (include "pleme-lib.flux.staged" .) "true" -}}
{{- if not ($d.sourceRef | default dict).name -}}
  {{- fail "flux: `flux.layerDefaults.sourceRef.name` is required whenever `flux.layers` is non-empty -- every Kustomization needs a source to apply from" -}}
{{- end -}}
{{- range $i, $l := $layers }}
{{- $edges := $l.dependsOn | default list }}
{{- if and (not $edges) (gt $i 0) }}
{{-   $edges = list (dict "name" (index $layers (sub $i 1)).name) }}
{{- end }}
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: {{ $l.name }}
  namespace: {{ $ns }}
  labels:
    {{- include "pleme-lib.labels" $ | nindent 4 }}
    pleme.io/flux-layer: {{ $l.name | quote }}
    pleme.io/flux-layer-index: {{ $i | quote }}
  {{- if $staged }}
  annotations:
    {{- include "pleme-lib.fluxcdPruneDisabled" $ | nindent 4 }}
    {{- include "pleme-lib.flux.stagedAnnotations" $ | nindent 4 }}
  {{- end }}
spec:
  interval: {{ $l.interval | default $d.interval | default "10m" }}
  path: {{ $l.path | quote }}
  {{- /* Brake 2. prune is FORCED off while staged: a suspended Kustomization
         that is later resumed with prune on can garbage-collect objects it
         does not yet know it manages. */}}
  prune: {{ if $staged }}false{{ else }}{{ $l.prune | default $d.prune | default true }}{{ end }}
  {{- if $staged }}
  suspend: true
  {{- end }}
  sourceRef:
    kind: {{ ($l.sourceRef | default $d.sourceRef).kind | default "GitRepository" }}
    name: {{ ($l.sourceRef | default $d.sourceRef).name }}
    {{- with (($l.sourceRef | default $d.sourceRef).namespace | default $ns) }}
    namespace: {{ . }}
    {{- end }}
  {{- with $edges }}
  dependsOn:
    {{- range . }}
    - name: {{ .name }}
      {{- with .namespace }}
      namespace: {{ . }}
      {{- end }}
    {{- end }}
  {{- end }}
  {{- with ($l.targetNamespace | default $d.targetNamespace) }}
  targetNamespace: {{ . }}
  {{- end }}
  timeout: {{ $l.timeout | default $d.timeout | default "5m" }}
  wait: {{ if kindIs "invalid" $l.wait }}{{ $d.wait | default true }}{{ else }}{{ $l.wait }}{{ end }}
  {{- with ($l.decryption | default $d.decryption) }}
  decryption:
    provider: {{ .provider | default "sops" }}
    {{- with .secretRef }}
    secretRef:
      name: {{ . | quote }}
    {{- end }}
  {{- end }}
  {{- with $l.patches }}
  patches:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
HelmRelease idiom defaults.

`crds: CreateReplace` on BOTH install and upgrade, always. A chart that ships
CRDs through Helm's native crds/ directory installs them once and NEVER
upgrades them -- the release goes green while the cluster silently keeps the
old schema, and any field added since is PRUNED off every custom resource
before a controller ever sees it. Nothing errors; the field simply is not
there. Measured on one cluster, 2026-07: an authorization field authored on
every CR of a kind had been dropped on write for weeks, so "is this object
authorized?" was unanswerable from the cluster itself.

The counterpart trap, so both halves are stated: some charts gate their CRDs
behind a values key and render them as ordinary templates instead. For those,
this field is INERT and the values key is the real gate -- setting it here and
believing the CRDs are handled is the same silence in the other direction.
*/}}
{{- define "pleme-lib.flux.release" -}}
{{- include "pleme-lib.flux.validate" . -}}
{{- $f := .Values.flux | default dict -}}
{{- $r := $f.release | default dict -}}
{{- if and $f.enabled $r.enabled -}}
{{- $c := $r.chart -}}
{{- $ns := include "pleme-lib.flux.namespace" . -}}
{{- $staged := eq (include "pleme-lib.flux.staged" .) "true" -}}
{{- $retries := $r.retries | default 3 -}}
{{- $crds := $r.crds | default "CreateReplace" -}}
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: {{ $r.name | default (include "pleme-lib.fullname" .) }}
  namespace: {{ $r.namespace | default .Release.Namespace }}
  labels:
    {{- include "pleme-lib.labels" . | nindent 4 }}
  {{- if or $staged $r.disableWait }}
  annotations:
    {{- if $staged }}
    {{- include "pleme-lib.fluxcdPruneDisabled" . | nindent 4 }}
    {{- include "pleme-lib.flux.stagedAnnotations" . | nindent 4 }}
    {{- end }}
    {{- if $r.disableWait }}
    {{- /* An ANNOTATION, not a YAML comment. `disableWait` says the release is
           Ready before its workload is, which is a real weakening of what
           Ready means — and the reason was written as `# {{ reason }}`, which
           Helm renders but the API server discards, so the applied object
           carried the weakening with no trace of why. An operator reading the
           live HelmRelease during an incident sees this; a comment in a
           rendered manifest they never see does not. */}}
    pleme.io/disable-wait-reason: {{ required "flux.release.disableWaitReason is required when disableWait is set — disableWait means Ready no longer implies the workload is up, and an unexplained one is indistinguishable from a mistake" $r.disableWaitReason | quote }}
    {{- end }}
  {{- end }}
spec:
  interval: {{ $r.interval | default "30m" }}
  {{- /* Not the Helm default (5m). A release that does CreateReplace across a
         CRD set, or rolls a Recreate-strategy workload onto thin capacity,
         routinely needs longer -- and a timeout that fires mid-swap leaves the
         release in a failed state that the next reconcile has to remediate
         rather than continue. */}}
  timeout: {{ $r.timeout | default "10m" }}
  {{- if $staged }}
  suspend: true
  {{- end }}
  {{- /* Detects a live hand-edit and reverts it: the GitOps half of law 3. */}}
  driftDetection:
    mode: {{ $r.driftDetection | default "enabled" }}
  {{- with $r.dependsOn }}
  dependsOn:
    {{- range . }}
    - name: {{ .name }}
      {{- with .namespace }}
      namespace: {{ . }}
      {{- end }}
    {{- end }}
  {{- end }}
  chart:
    spec:
      chart: {{ $c.name | quote }}
      {{- with $c.version }}
      version: {{ . | quote }}
      {{- end }}
      sourceRef:
        kind: {{ $c.sourceRef.kind | default "HelmRepository" }}
        name: {{ $c.sourceRef.name }}
        namespace: {{ $c.sourceRef.namespace | default $ns }}
  install:
    createNamespace: {{ $r.createNamespace | default false }}
    crds: {{ $crds }}
    {{- if $r.disableWait }}
    disableWait: true
    {{- end }}
    remediation:
      retries: {{ $retries }}
  upgrade:
    crds: {{ $crds }}
    {{- if $r.disableWait }}
    disableWait: true
    {{- end }}
    remediation:
      retries: {{ $retries }}
      {{- /* Without this, the LAST failure of the retry budget is left in
             place instead of being rolled back, so the release sits failed on
             a spec nobody chose. */}}
      remediateLastFailure: {{ $r.remediateLastFailure | default true }}
  {{- with $r.valuesFrom }}
  valuesFrom:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with $r.values }}
  values:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
The whole plumbing, in dependency order: sources exist before the layers that
reference them, and the release last.
*/}}
{{- define "pleme-lib.flux" -}}
{{- include "pleme-lib.flux.validate" . -}}
{{- /* Newline-separated, NOT `-}}`-joined: each sub-template's last emitted
       line has its trailing newline trimmed, so a right-trim here would weld
       the next document's `---` onto it and the whole render becomes one
       unparseable object. */}}
{{- include "pleme-lib.flux.sources" . }}
{{ include "pleme-lib.flux.layers" . }}
{{ include "pleme-lib.flux.release" . }}
{{- end }}
