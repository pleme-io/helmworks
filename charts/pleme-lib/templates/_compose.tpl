{{/*
pleme-lib: layer PRESCRIBED declarations over OBSERVED state, keyed by identity.

★ THE PROBLEM THIS NAMES. A chart that manages something already running has
two sources of truth, and they are not the same KIND of statement:

  DESCRIPTIVE  what the thing actually has, read off it. This is how adoption
               stays safe — the values are byte-identical to reality, so the
               first apply is a no-op rather than a mutation.

  PRESCRIPTIVE what a ROLE requires, independent of any instance.

★ THE PRESCRIPTION WINS, and that direction is the entire point. A profile
exists to say "whatever this box currently believes, its master is X".
Descriptive-wins would make it decorative: silently overridden by whatever the
instance already had, which is exactly the state it was written to correct.

★ MERGING IS PER-FIELD, NOT PER-ENTRY. An entry the prescription mentions keeps
every field the prescription did not speak about. This matters whenever the
consuming API treats the merged map as AUTHORITATIVE — a whole-entry replace
would delete every option the prescription simply had no opinion on, which is
data loss dressed as a merge.

★ ORDER IS FIRST-SEEN AND IT IS A CONTRACT. Observed entries establish the
order; a prescribed entry with no counterpart is appended. Consumers render
these in sequence, and some downstream systems care (position decides identity
in more places than anyone expects), so a resolver that returned a map would
make output depend on Go's deliberately-randomised iteration order.

Extracted from helmworks-pleme/charts/roteador-router, where it composed
device-derived UCI sections with role profiles. Nothing about it is router-
shaped: `keys` names the identity fields and `field` names the map to merge, so
the same primitive layers any intent over any observed state.

USAGE

  {{- $effective := include "pleme-lib.compose.layer" (dict
        "base"  .Values.sections          {{/* observed */}}
        "over"  $profileSections          {{/* prescribed */}}
        "keys"  (list "config" "section")
        "field" "values") | fromYamlArray -}}

  base   list   — observed entries. Establish order. Default empty.
  over   list   — prescribed entries. Win per-field. Default empty.
  keys   list   — field names forming the identity. Default ["name"].
  field  string — the map merged per-key. Default "values".

Returns a YAML-serialized list; parse with `fromYamlArray`.
*/}}
{{- define "pleme-lib.compose.layer" -}}
{{- $base := .base | default list -}}
{{- $over := .over | default list -}}
{{- /* ★ hasKey, NOT `| default`. Helm's `default` treats an empty list as
       absent, so `.keys | default (list "name")` silently turns an explicitly
       empty `keys` into ["name"] — which made the guard below UNREACHABLE.
       Caught by its own test failing to trip it: the assertion expected a
       refusal and got a clean render. A guard that cannot fire is worse than
       no guard, because it reads as protection. */ -}}
{{- $keys := list "name" -}}
{{- if hasKey . "keys" -}}{{- $keys = .keys | default list -}}{{- end -}}
{{- $field := .field | default "values" -}}
{{- if eq (len $keys) 0 -}}
  {{- fail "pleme-lib.compose.layer: `keys` is empty — with no identity fields every entry collides with every other, so the result would be one arbitrary survivor" -}}
{{- end -}}
{{- $acc := dict -}}
{{- $order := list -}}
{{- /* ── Observed first: they establish order ────────────────────────────
       A NUL joiner, not a dash: identity fields may legitimately contain the
       separator, and "a-b"+"c" colliding with "a"+"b-c" is a silent wrong
       merge rather than an error. NUL cannot appear in a YAML scalar. */ -}}
{{- range $e := $base -}}
  {{- $parts := list -}}
  {{- range $k := $keys -}}{{- $parts = append $parts (index $e $k | toString) -}}{{- end -}}
  {{- $id := join "\x00" $parts -}}
  {{- if not (hasKey $acc $id) -}}{{- $order = append $order $id -}}{{- end -}}
  {{- $_ := set $acc $id (deepCopy $e) -}}
{{- end -}}
{{- /* ── Prescribed second: win per-field, keep the rest ─────────────────── */ -}}
{{- range $e := $over -}}
  {{- $parts := list -}}
  {{- range $k := $keys -}}{{- $parts = append $parts (index $e $k | toString) -}}{{- end -}}
  {{- $id := join "\x00" $parts -}}
  {{- $prior := index $acc $id -}}
  {{- if $prior -}}
    {{- $merged := deepCopy $prior -}}
    {{- /* `merge` is destination-wins, so the PRESCRIBED map must be the
           destination for the prescription to win. Reversing these two
           arguments silently inverts the whole doctrine above and still
           renders, which is why it is called out here rather than trusted
           to be obvious. */ -}}
    {{- $vals := merge (deepCopy (default dict (index $e $field))) (default dict (index $prior $field)) -}}
    {{- $_ := set $merged $field $vals -}}
    {{- $_ := set $acc $id $merged -}}
  {{- else -}}
    {{- $order = append $order $id -}}
    {{- $_ := set $acc $id (deepCopy $e) -}}
  {{- end -}}
{{- end -}}
{{- $out := list -}}
{{- range $id := $order -}}{{- $out = append $out (index $acc $id) -}}{{- end -}}
{{- $out | toYaml -}}
{{- end }}
