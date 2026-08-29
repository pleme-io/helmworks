{{/*
pleme-lib.grafana — Grafana dashboards and provisioned alerts as sidecar-
discovered ConfigMaps: one ConfigMap per file, from a glob.

WHAT IT IS. A consuming chart drops JSON files into a directory and declares the
glob plus the label pair its target Grafana's k8s-sidecar selects on. Every
matching file becomes its own ConfigMap. Adding a board is dropping a file in —
there is no template change and no list to keep in sync, which is the whole
point: a hand-maintained list of payloads drifts against the directory and the
drift is invisible until somebody notices a board that was never delivered.

Nothing here interprets the payload. A ConfigMap holding a JSON document has no
execution semantics, and that is a STRUCTURAL property of this template rather
than a setting: the only kind it can emit is gated by an allowlist (below), so
there is no code path to audit for whether the setting was applied. This is the
shape a hardened boundary will accept without a code review, where an
operator-in-the-boundary design will not.

WHY ONE ConfigMap PER FILE rather than one holding the whole set. A ConfigMap is
a single etcd value with a hard size ceiling; a bundle that grows past it fails
at APPLY time with an opaque error, long after the render that caused it.
Per-file keeps each object small and makes a bad payload blame exactly one file.

NOT A DUPLICATE OF pleme-lib.observabilityBundle. That template takes an
explicit LIST of dashboard entries, each naming its own inline JSON or single
file — the right shape when a chart ships two or three boards it wants to name
individually. This one takes a GLOB, for the case where the directory is the
source of truth and the count is expected to grow. They compose; neither reads
the other's values.

THE TRADE, stated because it is real: no controller means no drift detection. An
edit made in the Grafana UI is lost at the sidecar's next provisioning cycle and
nothing REPORTS that it happened; a ConfigMap deleted outright is not restored.
Re-delivery is a re-apply.

──────────────────────────────────────────────────────────────────────────────
THE TRAPS THIS ENCODES. Each one was paid for on a real cluster.

(1) THE PAYLOAD IS INSERTED VERBATIM VIA `.Files.Get`, NEVER THROUGH `tpl`.
    Grafana's own syntax collides with Helm's. A panel legend is written
    `{{label}}` and an alert annotation is written `{{ $labels.pod }}` — both are
    ordinary Grafana template syntax that GRAFANA evaluates. Handing them to the
    Helm engine is a render error at best and, where the expression happens to
    parse, a silently rewritten dashboard that ships wrong. There is no `tpl`
    call anywhere in this file and there must never be one. Where a payload
    genuinely needs a value bound at package time, that is what the literal-token
    pass below is for, and it is `replace` — a byte substitution that cannot
    evaluate anything.

(2) AN EMPTY GLOB IS A RENDER ERROR, NOT AN EMPTY RENDER.
    A chart that declares dashboards, matches no files, applies cleanly and
    reports success has delivered nothing — and looks identical from the outside
    to a delivery that worked. That is the exact failure this mechanism exists to
    remove, so an arm that is enabled and matches zero files calls `fail`.
    If this fires only for a PACKAGED chart while the same glob matches from the
    directory, suspect `.helmignore`: it drops files out of the package silently
    and leaves no trace in the render.

(3) AFTER SUBSTITUTION, A SURVIVING TOKEN IS A RENDER ERROR.
    Substitution exists because a PROVISIONED ALERT RULE cannot defer its
    datasource the way a dashboard panel can. A board resolves `${datasource}`
    from a dashboard template variable; a rule is evaluated with no dashboard and
    no variable in scope, so its datasource UID is a literal that has to be bound
    at package time. A wrong or unbound UID does NOT fail the render on its own —
    the rules provision, apply cleanly, and then sit in an error state at
    evaluation with datasource-not-found. That is why the check is here and not
    left to the cluster: the residual scan refuses any `__UPPER_SNAKE__` token
    still present in the emitted bytes, whether or not the caller declared it.
    The convention is deliberate and greppable — a reader can search the payload
    and see exactly what moves.
    The reverse is checked too: a token DECLARED in values that no matched file
    contains is refused, because a substitution map that binds nothing is how a
    renamed placeholder goes unnoticed while the render stays green.

(4) AN ALLOWLIST OF EMITTED KINDS.
    Every object goes out through `pleme-lib.grafana.kindGate`, which fails
    unless the kind is in the resolved allowlist. `grafana.allowedKinds` may
    NARROW the built-in set; naming anything outside it is a render error rather
    than a widening. A mechanism that reads arbitrary files off a glob must never
    be able to publish something other than the kind it promised — otherwise a
    later edit that "just" emits the file's own content turns a stray file into
    an arbitrary object, and the glob is the attacker-shaped input.

(5) THE SIDECAR LABEL KEY AND VALUE HAVE NO DEFAULTS, AND NEITHER DOES THE
    FOLDER. A ConfigMap carrying the wrong sidecar label is not an error: it
    applies, it is simply never loaded, and the boards are quietly absent — which
    is indistinguishable from success. A hardened Grafana distribution renames
    these, so a default here would be a guess whose failure mode is silence. The
    folder likewise: it is a fact about the target Grafana, not about this
    library, and it is required so a delivery cannot scatter itself across
    whatever fallback the sidecar happens to use. The folder ANNOTATION KEY does
    have a default, and the distinction is on purpose — the LABEL decides whether
    the object loads at all (silent total failure), the annotation only decides
    where it lands (visible, and recoverable by moving it).

(6) LABELS ARE MERGED AS A MAP, NEVER APPENDED AS TEXT.
    `pleme-lib.labels` renders a text block. Appending an override line to it
    emits a DUPLICATE YAML KEY, which strict parsers reject and lenient ones
    resolve last-wins — and the load-bearing sidecar label is precisely the key a
    consumer is most likely to also set in `additionalLabels`. This template
    parses that block back into a map and merges, so two identical keys are
    unrepresentable rather than guarded, and the sidecar pair wins the merge.

──────────────────────────────────────────────────────────────────────────────
USAGE — the consuming chart's templates/grafana.yaml is one line:

  {{- include "pleme-lib.grafana" . }}

VALUES (all under `grafana:`; the whole surface is off by default):

  grafana:
    enabled: false
    folder: ""                    # REQUIRED when enabled — no default
    namePrefix: ""                # default: pleme-lib.fullname
    allowedKinds: ["ConfigMap"]   # may narrow the built-in set, never widen it
    sidecar:
      folderAnnotation: grafana_folder
    dashboards:
      enabled: false
      glob: ""                    # REQUIRED, e.g. "dashboards/*.json"
      labelKey: ""                # REQUIRED — no default
      labelValue: ""              # REQUIRED — no default
      tokens: {}                  # normally EMPTY: a board defers its datasource
                                  # to a ${datasource} dashboard variable
    alerts:
      enabled: false
      glob: ""                    # REQUIRED, e.g. "alerts/*.json"
      labelKey: ""                # REQUIRED — no default
      labelValue: ""              # REQUIRED — no default
      tokens:                     # literal token -> value, bound at package time
        __METRICS_DS_UID__: ""
    extraLabels: {}
    extraAnnotations: {}

Either arm may ship alone. A first delivery into a new boundary is usually
dashboards only: a board that renders wrong is a nuisance, a rule that fires
wrong is a page for somebody else's on-call.

OWNERSHIP BOUNDARY vs `pleme-lib._observabilityBundle.dashboardCM`. That helper
takes dashboards as VALUES (one ConfigMap per inline entry) and hardcodes the
sidecar label. This template takes them from a GLOB on disk and requires the
label pair to be declared. A chart uses one or the other: they deliver to the
same sidecar, so using both means two producers for one dashboard set and the
last one applied wins. Written down rather than merged — the values-driven and
file-driven shapes fit different authoring stories, and one template covering
both would fit neither well (★★ CONVERGENT-EVIDENCE).
*/}}

{{- define "pleme-lib.grafana" -}}
{{- $root := . -}}
{{- $g := .Values.grafana | default dict -}}
{{- if $g.enabled -}}
{{- $folder := $g.folder | default "" | toString -}}
{{- if eq $folder "" -}}
{{- fail "pleme-lib.grafana: set `grafana.folder` — the Grafana folder every board and rule group lands in. There is no default: a folder name is a fact about the target Grafana, not about this library, and a guessed one scatters the delivery into whatever fallback folder the sidecar happens to use." -}}
{{- end -}}
{{- $dash := $g.dashboards | default dict -}}
{{- $alert := $g.alerts | default dict -}}
{{- if and (not $dash.enabled) (not $alert.enabled) -}}
{{- fail "pleme-lib.grafana: `grafana.enabled` is true but both arms are off — set `grafana.dashboards.enabled` and/or `grafana.alerts.enabled`. Opting in and delivering nothing renders clean, applies clean, and ships no observability at all; that is the vacuity this template refuses." -}}
{{- end -}}
{{- $builtinKinds := list "ConfigMap" -}}
{{/* `default` treats an empty list as empty, so `$g.allowedKinds | default
     $builtinKinds` silently rewrites `allowedKinds: []` back to the FULL
     allowlist — the same zero-value trap _scaletozero.tpl documents for
     integers. Presence, not emptiness, decides whether values were told. */}}
{{- $allow := $builtinKinds -}}
{{- if hasKey $g "allowedKinds" -}}
{{- $allow = ($g.allowedKinds | default (list)) -}}
{{- end -}}
{{- range $k := $allow -}}
{{- if not (has $k $builtinKinds) -}}
{{- fail (printf "pleme-lib.grafana: `grafana.allowedKinds` names %q, which this mechanism has no code path to emit. The allowlist may only narrow the built-in set %v. Widening it is how a mechanism that reads arbitrary files off a glob starts publishing arbitrary objects." $k $builtinKinds) -}}
{{- end -}}
{{- end -}}
{{- $prefix := $g.namePrefix | default (include "pleme-lib.fullname" $root) -}}
{{- $folderAnnotation := ($g.sidecar | default dict).folderAnnotation | default "grafana_folder" -}}
{{- $common := dict "root" $root "folder" $folder "folderAnnotation" $folderAnnotation "prefix" $prefix "allow" $allow "extraLabels" ($g.extraLabels | default dict) "extraAnnotations" ($g.extraAnnotations | default dict) -}}
{{- if $dash.enabled }}
{{ include "pleme-lib.grafana.set" (merge (dict "arm" $dash "component" "dashboard" "key" "grafana.dashboards") (deepCopy $common)) -}}
{{- end }}
{{- if $alert.enabled }}
{{ include "pleme-lib.grafana.set" (merge (dict "arm" $alert "component" "alerting" "key" "grafana.alerts") (deepCopy $common)) -}}
{{- end }}
{{- end -}}
{{- end -}}

{{/*
pleme-lib.grafana.set — ONE arm: glob -> a ConfigMap per matched file.

Argument, one dict:
  root              the chart root context
  arm               the arm's values subtree (glob / labelKey / labelValue / tokens)
  component         "dashboard" | "alerting" — becomes the name segment and the
                    app.kubernetes.io/component label
  key               the values path this arm lives at, so every fail() can name
                    the exact key that fixes it
  folder            the Grafana folder (already validated non-empty)
  folderAnnotation  the annotation key the sidecar reads the folder from
  prefix            ConfigMap name prefix
  allow             the resolved kind allowlist
  extraLabels       stamped onto every emitted object
  extraAnnotations  stamped onto every emitted object

Every value is captured into a `$`-variable BEFORE the range: `range` rebinds
`.`, so a `.field` read inside the loop body silently resolves against the
matched file's value instead of this dict.
*/}}
{{- define "pleme-lib.grafana.set" -}}
{{- $root := .root -}}
{{- $arm := .arm -}}
{{- $component := .component -}}
{{- $key := .key -}}
{{- $folder := .folder -}}
{{- $folderAnnotation := .folderAnnotation -}}
{{- $prefix := .prefix -}}
{{- $allow := .allow -}}
{{- $extraLabels := .extraLabels -}}
{{- $extraAnnotations := .extraAnnotations -}}
{{- $glob := $arm.glob | default "" | toString -}}
{{- if eq $glob "" -}}
{{- fail (printf "pleme-lib.grafana: set `%s.glob` — the chart-relative pattern whose matches become ConfigMaps (e.g. \"dashboards/*.json\"). There is no default: the directory layout belongs to the consuming chart, and a guessed one would silently match nothing." $key) -}}
{{- end -}}
{{- $labelKey := $arm.labelKey | default "" | toString -}}
{{- if eq $labelKey "" -}}
{{- fail (printf "pleme-lib.grafana: set `%s.labelKey` — the label key the target Grafana's k8s-sidecar selects on. There is no default because the wrong key is NOT an error: the ConfigMap applies, the sidecar never loads it, and the delivery is indistinguishable from a successful one. Confirm it against the target Grafana; nothing on this side can check it." $key) -}}
{{- end -}}
{{- $labelValue := $arm.labelValue | default "" | toString -}}
{{- if eq $labelValue "" -}}
{{- fail (printf "pleme-lib.grafana: set `%s.labelValue` — the value the sidecar matches on for label %q. Same silent-miss as the key: a mismatched value loads nothing and reports nothing." $key $labelKey) -}}
{{- end -}}
{{- $tokens := $arm.tokens | default dict -}}
{{- $found := 0 -}}
{{- $seenNames := dict -}}
{{- $seenTokens := dict -}}
{{- range $path, $_ := $root.Files.Glob $glob }}
{{- $found = add1 $found -}}
{{- $file := base $path -}}
{{- if not (regexMatch "^[-._a-zA-Z0-9]+$" $file) -}}
{{- fail (printf "pleme-lib.grafana: %q matched `%s.glob` but its filename is not a legal ConfigMap data key ([-._a-zA-Z0-9]+). Narrow the glob — a pattern loose enough to sweep in a stray file is how a non-payload ends up published as one." $path $key) -}}
{{- end -}}
{{/* NOT the pipeline form: sprig is `regexReplaceAll REGEX STRING REPL`, so
     `$x | regexReplaceAll "re" "-"` passes $x as the REPLACEMENT and returns
     the input unchanged — a sanitizer that silently does nothing, and an
     unsluggable-name guard below that can never fire. Measured: it left
     `service_overview` intact, which is not a legal DNS-1123 name and is
     rejected by the API server at apply time — the exact failure this is
     here to catch at render. */}}
{{- $stem := $file | trimSuffix (ext $file) | lower -}}
{{- $slug := regexReplaceAll "[^a-z0-9]+" $stem "-" | trimPrefix "-" | trimSuffix "-" -}}
{{- if eq $slug "" -}}
{{- fail (printf "pleme-lib.grafana: %q leaves no DNS-1123 name after slugging, so it cannot name a ConfigMap. Rename the file to something with at least one alphanumeric character." $path) -}}
{{- end -}}
{{- $raw := $root.Files.Get $path -}}
{{- if eq (trim $raw) "" -}}
{{- fail (printf "pleme-lib.grafana: %q matched `%s.glob` but is empty. An empty payload renders a ConfigMap that applies cleanly and loads as nothing — the same silent success every other guard here exists to refuse. If the file has content on disk, `.helmignore` is excluding it from the package." $path $key) -}}
{{- end -}}
{{- $body := $raw -}}
{{- range $tok, $val := $tokens -}}
{{- if contains $tok $raw -}}{{- $_ := set $seenTokens $tok true -}}{{- end -}}
{{- $body = replace $tok ($val | toString) $body -}}
{{- end -}}
{{- $residual := regexFind "__[A-Z0-9][A-Z0-9_]*__" $body -}}
{{- if $residual -}}
{{- fail (printf "pleme-lib.grafana: %q still carries the placeholder %s after substitution — bind it in `%s.tokens`. An unsubstituted placeholder is the worst failure this mechanism has: the object renders, applies and reports healthy while the rule or board is bound to a literal string that resolves to nothing at evaluation time." $path $residual $key) -}}
{{- end -}}
{{- if gt (len $body) 1000000 -}}
{{- fail (printf "pleme-lib.grafana: %q is too large to carry in a ConfigMap, which is one etcd value with a hard ceiling. Split the payload across files; the glob will pick both up. Left alone this fails at apply time with an opaque error rather than here." $path) -}}
{{- end -}}
{{- $cmName := printf "%s-%s-%s" $prefix $component $slug | trunc 63 | trimSuffix "-" -}}
{{- if hasKey $seenNames $cmName -}}
{{- fail (printf "pleme-lib.grafana: %q and %q both reduce to the ConfigMap name %q after the 63-character truncation. Two objects with one name is a last-writer-wins delivery in which one payload silently never reaches the cluster. Rename a file or shorten `grafana.namePrefix`." (index $seenNames $cmName) $path $cmName) -}}
{{- end -}}
{{- $_ := set $seenNames $cmName $path -}}
---
apiVersion: v1
kind: {{ include "pleme-lib.grafana.kindGate" (dict "kind" "ConfigMap" "allow" $allow) }}
metadata:
  name: {{ $cmName }}
  namespace: {{ include "pleme-lib.namespace" $root }}
  labels:
    {{- include "pleme-lib.grafana.labelBlock" (dict "root" $root "labelKey" $labelKey "labelValue" $labelValue "component" $component "extra" $extraLabels) | nindent 4 }}
  annotations:
    {{ $folderAnnotation }}: {{ $folder | quote }}
    {{- range $k, $v := $extraAnnotations }}
    {{ $k }}: {{ $v | quote }}
    {{- end }}
data:
  {{ $file }}: |-
{{ $body | indent 4 }}
{{- end }}
{{- if eq $found 0 -}}
{{- fail (printf "pleme-lib.grafana: `%s.enabled` is true but `%s.glob` (%q) matched nothing. An empty render here applies cleanly, reports success and delivers no boards or rules at all — the failure this template exists to make loud. If the files are present in the working tree, `.helmignore` is dropping them out of the packaged chart, silently and with no trace in the render." $key $key $glob) -}}
{{- end -}}
{{- range $tok, $val := $tokens -}}
{{- if not (hasKey $seenTokens $tok) -}}
{{- fail (printf "pleme-lib.grafana: `%s.tokens` declares %s but no file matched by `%s.glob` contains it. A substitution that binds nothing is how a renamed placeholder goes unnoticed while the render stays green — remove the entry, or fix the token in the payload." $key $tok $key) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
pleme-lib.grafana.kindGate — the only way an object leaves this template.

Argument, one dict: { kind, allow }. Returns the kind, or fails.

This is on the emission path rather than beside it: the rendered `kind:` line IS
this include, so an emission that is not gated cannot be written without
deleting the gate. A mechanism whose input is "whatever files match a glob" must
be structurally incapable of publishing a kind it did not promise.

Tier-honest, so nobody mistakes this for more than it is. Two things are checked
and each is reachable: the entry refuses an allowlist naming a kind outside the
built-in set (a widening), and this gate refuses an emission the resolved
allowlist does not cover — reached today by narrowing the allowlist to empty.
What is NOT reachable while the built-in set has exactly one member is a
narrowing to some OTHER legal kind, because there is no other legal kind. The
gate earns its place as the structure that makes a second emission impossible to
add without passing through it, not as a check that fires on a wrong value.
*/}}
{{- define "pleme-lib.grafana.kindGate" -}}
{{- if not (has .kind .allow) -}}
{{- fail (printf "pleme-lib.grafana: refusing to emit kind %q — it is not in the resolved allowlist %v. Set `grafana.allowedKinds` to include it only if this template actually has a code path for it; the allowlist is a promise about what a glob-driven emitter can publish, not a filter to loosen. An empty allowlist lands here too — it would otherwise refuse every object while still reporting a clean render." .kind .allow) -}}
{{- end -}}
{{- .kind -}}
{{- end -}}

{{/*
pleme-lib.grafana.labelBlock — the label set, built as a MAP.

Argument, one dict: { root, labelKey, labelValue, component, extra }.

`pleme-lib.labels` renders TEXT. Appending an override line to a text block emits
a duplicate YAML key: strict parsers reject the object outright and lenient ones
resolve last-wins, so the load-bearing sidecar label can be silently overwritten
by a consumer's `additionalLabels`. Parsing the block back into a map and merging
makes the duplicate unrepresentable instead of guarded, and fixes the precedence
in one place: the sidecar pair wins over `grafana.extraLabels`, which wins over
the common block. The sidecar label is what decides whether the payload is loaded
at all, so nothing may outrank it.
*/}}
{{- define "pleme-lib.grafana.labelBlock" -}}
{{- $common := fromYaml (include "pleme-lib.labels" .root) -}}
{{- if hasKey $common "Error" -}}
{{- fail (printf "pleme-lib.grafana: the pleme-lib.labels block did not parse as a map (%v), so the sidecar label cannot be merged without risking a duplicate YAML key. Fix `additionalLabels` in the consuming chart." (index $common "Error")) -}}
{{- end -}}
{{- $sidecar := dict .labelKey (.labelValue | toString) "app.kubernetes.io/component" .component -}}
{{- $merged := merge $sidecar (deepCopy (.extra | default dict)) $common -}}
{{/* Every label VALUE is coerced to a string. A bare `0` or `true` reaching
     `toYaml` from a values map renders unquoted, which is an integer or a
     boolean in YAML, and the apiserver rejects the whole object at admission —
     a late, opaque failure for a value that was only ever meant to be a tag. */}}
{{- $out := dict -}}
{{- range $k, $v := $merged -}}{{- $_ := set $out $k ($v | toString) -}}{{- end -}}
{{- toYaml $out -}}
{{- end -}}
