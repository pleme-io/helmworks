{{/*
pleme-lib.composition — Crossplane Composition pipeline helpers.

Renders a function-kcl pipeline step with `target: XR` for typed
status reflection (the canonical pattern documented in
pleme-io/theory/CROSSPLANE-COMPOSITION-STATUS.md).

The 6-item contract for the consumer-authored KCL source:

  1. Output shape: `items = [{XR-with-status}]`
     (NOT a top-level `dxr = {...}` — function-kcl passes that
     through as a literal field name on the XR; SSA rejects with
     ".dxr: field not declared in schema")

  2. NO composed-resource items[]
     (only items[0] = the XR; otherwise SSA path traversal trips
     on field names with leading dots like ".dockerconfigjson"
     in image-pull Secret data — the Resources-step KCL emits
     those, not the XR-step)

  3. Cherry-pick metadata.name only
     (NOT `metadata = _oxr.metadata` wholesale — brings
     managedFields; SSA rejects)

  4. Every status field must be declared in the XRD's
     openAPIV3Schema.properties.status.properties

  5. Skip conditions[] (or pass time as KCLInput param) — KCL
     has no stdlib `now()`; metav1.Condition validation requires
     lastTransitionTime independent of the XRD schema

  6. Read inputs from option("params").ocds[<observer-name>]
     — observer is a provider-kubernetes Object MR emitted by
     the Resources step that observes the result ConfigMap

Derivation cost: 5 chart bumps + 5 wedged drills (#18-22 of
pitr-borealis). See theory doc for the full iteration log.

Usage in a consumer chart's templates/composition.yaml:

  spec:
    mode: Pipeline
    pipeline:
      - step: orchestrate
        functionRef: { name: function-kcl }
        input:
          apiVersion: krm.kcl.dev/v1alpha1
          kind: KCLInput
          spec:
            target: Resources
            source: |
  {{- "{{" }} tpl (.Files.Get "kcl/main.k") . | indent 12 {{ "}}" }}
      {{- include "pleme-lib.composition.statusReflectStep" (dict
            "step"      "reflect-xr-status"
            "kclSource" (tpl (.Files.Get "kcl/status.k") .)) | nindent 6 }}

Validated reference impl:
  borealis/borealis-environments/saas/kubernetes/helm/pitr-borealis
  chart 0.9.21 (drill #23 correlation 2b70f82b).
*/}}

{{- define "pleme-lib.composition.statusReflectStep" -}}
{{- $step := .step | default "reflect-xr-status" -}}
{{- $src  := required "pleme-lib.composition.statusReflectStep: .kclSource is required (the consumer-authored KCL fragment that emits items[0] = XR with new status)" .kclSource -}}
- step: {{ $step }}
  functionRef:
    name: function-kcl
  input:
    apiVersion: krm.kcl.dev/v1alpha1
    kind: KCLInput
    spec:
      # `target: XR` — function-kcl reads items[0] from the KCL
      # output and uses it as the new desired XR. The status fields
      # propagate to <xr-kind>.status via server-side apply. See
      # pleme-io/theory/CROSSPLANE-COMPOSITION-STATUS.md for the
      # 6-item contract this KCL source must satisfy.
      target: XR
      source: |
{{ $src | indent 8 }}
{{- end -}}
