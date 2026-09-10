{{/*
pleme-lib: the pangea-operator declaration surface.

★ PLATFORM-MEDIATED INFRASTRUCTURE says the only verbs are DECLARE and OBSERVE:
a chart hands pangea-operator an InfrastructureTemplate and the operator
reconciles it. Until now every chart that wanted to declare infrastructure
hand-rolled that CR, so the doctrine had no shared implementation — which is
how a chart ends up with a subtly different spec surface than its neighbour and
nobody notices, because both render valid YAML.

Extracted from helmworks-pleme/charts/roteador-router, the first chart to
declare infrastructure this way. Nothing here is router-shaped.

────────────────────────────────────────────────────────────────────────────
pleme-lib.pangea.approvalPartition — split resources by approval class

★ WHY A PARTITION AND NOT A FLAG. `autoApprove` is per-CR, not per-resource. A
chart that wants some resources self-healing and others gated must therefore
emit MORE THAN ONE CR, and this computes that split.

★ THE CO-COMMIT REFUSAL IS THE LOAD-BEARING PART, and it generalises further
than it looks. Many executors stage writes into a shared area keyed by
something coarser than the resource — UCI stages per PACKAGE and
`commit <package>` writes out everything staged there; a Terraform workspace
commits per state file. When two approval classes share such a group, the
self-healing CR's commit also publishes the gated CR's un-approved changes, and
the gate is decorative while still looking present.

So a straddling group is REFUSED at render rather than emitted. `coCommitKey`
names the field that identifies the group; pass "" when the executor has no
such grouping and the check is skipped.

  {{- $byClass := include "pleme-lib.pangea.approvalPartition" (dict
        "resources"   $effective
        "default"     .Values.autoApprove
        "coCommitKey" "config"
        "kind"        "UCI package") | fromYaml -}}

Returns a YAML map: class ("auto"/"gated") -> list of resources.

────────────────────────────────────────────────────────────────────────────
pleme-lib.pangea.infrastructureTemplate — emit one CR

  {{- include "pleme-lib.pangea.infrastructureTemplate" (dict
        "name" "roteador-natal" "namespace" "default"
        "pangeaNamespace" "roteador" "executor" "magma"
        "autoApprove" true "inline" $tfJson "ctx" $) -}}
*/}}

{{- define "pleme-lib.pangea.approvalPartition" -}}
{{- $resources := .resources | default list -}}
{{- $default := .default | default false -}}
{{- $coKey := .coCommitKey | default "" -}}
{{- $kind := .kind | default "co-commit group" -}}
{{- $byClass := dict -}}
{{- $owner := dict -}}
{{- range $i, $r := $resources -}}
  {{- /* Per-resource override wins over the chart-level default. hasKey, not
         truthiness: `autoApprove: false` on a resource must be an override,
         and a plain `if` would read it as absent and silently inherit. */ -}}
  {{- $eff := $default -}}
  {{- if hasKey $r "autoApprove" -}}{{- $eff = index $r "autoApprove" -}}{{- end -}}
  {{- $class := ternary "auto" "gated" $eff -}}
  {{- if $coKey -}}
    {{- $group := index $r $coKey -}}
    {{- if $group -}}
      {{- $prior := index $owner ($group | toString) -}}
      {{- if and $prior (ne $prior $class) -}}
        {{- fail (printf "%s %q is claimed by BOTH approval classes (resources[%d] is %s, an earlier one is %s). The executor commits per group, so the self-healing CR would publish the gated CR's un-approved changes and the gate would be decorative. Put every resource of one group in one class, or split the group." $kind ($group | toString) $i $class $prior) -}}
      {{- end -}}
      {{- $_ := set $owner ($group | toString) $class -}}
    {{- end -}}
  {{- end -}}
  {{- $_ := set $byClass $class (append (default (list) (index $byClass $class)) $r) -}}
{{- end -}}
{{- $byClass | toYaml -}}
{{- end }}

{{- define "pleme-lib.pangea.infrastructureTemplate" -}}
{{- $name := .name | required "pleme-lib.pangea.infrastructureTemplate: `name` is required — an unnamed CR cannot be reconciled or found again" -}}
{{- $ns := .namespace | default "default" -}}
apiVersion: pangea.pleme.io/v1alpha1
kind: InfrastructureTemplate
metadata:
  name: {{ $name | quote }}
  {{- /* ★ PINNED, never `.Release.Namespace`. The operator watches a fixed
         namespace, so a CR that follows the release lands somewhere nothing
         reconciles: it applies cleanly, reports nothing, and does nothing. */}}
  namespace: {{ $ns | quote }}
  {{- with .labels }}
  labels:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  pangeaNamespace: {{ .pangeaNamespace | required "pleme-lib.pangea.infrastructureTemplate: `pangeaNamespace` is required — it is the state boundary, and defaulting it would let two unrelated declarations share one state file" | quote }}
  executor: {{ .executor | default "magma" | quote }}
  dialect: {{ .dialect | default "json" | quote }}
  {{- /* ★ Rendered as a real bool. Quoted, the operator's deserializer sees a
         string and the field silently reads as absent. */}}
  autoApprove: {{ .autoApprove | default false }}
  {{- with .suspend }}
  suspend: {{ . }}
  {{- end }}
  {{- with .driftDetectionInterval }}
  driftDetectionInterval: {{ . | quote }}
  {{- end }}
  {{- with .approvedPlanHash }}
  approvedPlanHash: {{ . | quote }}
  {{- end }}
  {{- with .variables }}
  variables:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  source:
    inline: |
      {{- .inline | required "pleme-lib.pangea.infrastructureTemplate: `inline` is required — a template with no body reconciles to an empty plan, which reads as success" | nindent 6 }}
{{- end }}
