# Compliance Overlays — Design

**Status:** Design proposal. Implementation TBD; this document is the
specification.

**Goal (verbatim user direction):**

> "A neat structured of layered overlays is the best way to express this
> idea … we should really think about what exact helm pattern is best for
> expressing the entire compliance landscape … so over time we can build
> consistently and be able to express the entire layered ecosystem of
> compliance for specific use cases in a provable way where primitives
> are generated for that type."

---

## 1. The problem with the current shape

`pleme-lib` 0.8.0 ships ~13 `_compliance_*.tpl` files, each implementing
one concern (security, network, audit, RBAC, authn, airgap, mirror,
supplychain, fips, dod-IL, …). Each has its own `validate`,
`annotations`, `manifestData`, `policies` definitions. The central
`compliance.validate` is a hand-edited chain of `include` calls, the
control-coverage list is a string built from hand-edited conditionals,
and the manifest ConfigMap is a hand-edited list of `nindent` calls.

Adding a fourteenth concern (HIPAA, PCI-DSS, ISO 27001, NIS2, BSI C5,
DoD-IL6 hardware attestation, …) requires editing **five** central
files: `_compliance.tpl::validate`, `_compliance.tpl::controls`,
`_compliance_manifest.tpl`, `_helpers.tpl::resourceAnnotations`,
`values.yaml`. Each addition risks breaking the others; the regression
that landed mid-Wave 4 (Layer 4 firing too aggressively at FedRAMP-High)
is a direct symptom of this brittleness.

The deeper problem: the *composition logic* is duplicated everywhere
instead of being a single typed primitive.

---

## 2. The pattern

Compliance is a **typed registry of overlays**. A workload chart picks
its overlays by name; the registry composes them into the rendered
output. The composition rule is one typed function, not a 200-line
`compliance.validate`.

```yaml
compliance:
  overlays:
    - fedramp-high
    - airgap
    - supplychain
    - fips
    - dod-il5
```

Each overlay is a **provably typed module** with a fixed surface:

```
overlay <name>:
  validate          → fail() invariants
  annotations       → metadata fragments
  labels            → metadata fragments
  manifestData      → ConfigMap fragments
  policies          → auto-rendered K8s objects (NetworkPolicy, etc.)
  controls          → list of NIST control IDs covered
  requires          → list of overlay names that must apply with this one
  config            → the typed values shape this overlay accepts
  testCorpus        → the negative+positive tests proving this overlay
```

Overlays compose by union: applying `[A, B, C]` is equivalent to
applying `A`, then `B`, then `C`, with `requires` forming a transitive
closure.

---

## 3. Why this is provable

The proof in `COMPLIANCE-PROOF.md` becomes mechanical:

```
Claim: applying overlay set {O₁, …, Oₙ} produces a workload that satisfies
       the union of {O₁.controls, …, Oₙ.controls}.

Proof: by induction on |overlays|.
  Base: |overlays| = 0 — empty set, vacuously satisfies the empty
        control set.
  Step: applying overlay Oᵢ on top of a satisfying workload
        either fails template render (Oᵢ.validate raised fail()) OR
        produces a workload satisfying Oᵢ.controls additionally
        (Oᵢ.policies + Oᵢ.annotations are emitted; Oᵢ.validate
        confirmed every invariant).

The proof is mechanical because:
  - Each overlay's validate covers EVERY control in its controls list
    (enforced by a per-overlay test corpus).
  - The overlay registry walks the list deterministically.
  - There is no hidden coupling: an overlay can declare requires but
    cannot rely on side-effects of other overlays.
```

The CI gate becomes: for every overlay in the registry, both its
positive and negative test corpora must pass. The control-coverage
table is the union of every applied overlay's `controls` field — and
since `controls` is auto-generated from a typed declaration, the table
matches reality by construction.

---

## 4. The Helm-level realization

Helm's templating is awkward for typed-list-of-typed-things, but it has
exactly the primitives we need:

### 4.1 Overlay registration

Each `_overlay_<name>.tpl` declares:

```gotemplate
{{- define "pleme-lib.overlay.fedramp-high" -}}
name: fedramp-high
requires: []
controls: |
  AC-3,AC-4,AC-6,AC-6(1),AC-6(7),AC-17,AU-2,AU-3,AU-11,AU-12,
  CM-2,CM-6,CM-7,CM-8,IA-2,IA-2(1),IA-3,IA-5,
  SC-5,SC-7,SC-7(4),SC-7(5),SC-8,SC-12,SC-13,SC-22,SC-28,SI-4,SI-7,SI-16
config-schema: "fedramp-high"
{{- end }}

{{- define "pleme-lib.overlay.fedramp-high.validate" -}}
{{- /* invariants */ -}}
{{- end }}

{{- define "pleme-lib.overlay.fedramp-high.annotations" -}}
compliance.pleme.io/overlay-fedramp-high: "true"
{{- end }}

{{- define "pleme-lib.overlay.fedramp-high.policies" -}}
{{- /* NetworkPolicies, etc. */ -}}
{{- end }}
```

### 4.2 Central dispatch

```gotemplate
{{- define "pleme-lib.compliance.validate" -}}
{{- $overlays := include "pleme-lib.compliance.resolveOverlays" . | fromYamlArray -}}
{{- range $overlay := $overlays -}}
  {{- include (printf "pleme-lib.overlay.%s.validate" $overlay) $ -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.compliance.annotations" -}}
{{- $overlays := include "pleme-lib.compliance.resolveOverlays" . | fromYamlArray -}}
{{- range $overlay := $overlays -}}
  {{- include (printf "pleme-lib.overlay.%s.annotations" $overlay) $ -}}
{{- end -}}
{{- end }}

{{- define "pleme-lib.compliance.policies" -}}
{{- $overlays := include "pleme-lib.compliance.resolveOverlays" . | fromYamlArray -}}
{{- range $overlay := $overlays -}}
  {{- include (printf "pleme-lib.overlay.%s.policies" $overlay) $ -}}
{{- end -}}
{{- end }}
```

### 4.3 Closure resolution

`resolveOverlays` walks `.Values.compliance.overlays`, expands each
overlay's `requires`, deduplicates, and returns the topologically
ordered list:

```gotemplate
{{- define "pleme-lib.compliance.resolveOverlays" -}}
{{- $declared := .Values.compliance.overlays | default list -}}
{{- $resolved := list -}}
{{- range $declared -}}
  {{- $req := include (printf "pleme-lib.overlay.%s.requires" .) $ | fromYamlArray -}}
  {{- range $req -}}
    {{- $resolved = append $resolved . -}}
  {{- end -}}
  {{- $resolved = append $resolved . -}}
{{- end -}}
{{- $resolved | uniq | toYaml -}}
{{- end }}
```

(The actual implementation is iterative until fixpoint, since `requires`
can transitively depend.)

---

## 5. The use-case primitive

The user's directive: *"primitives are generated for that type"*.

Concretely: every recurring use-case (a regulated SaaS workload, a
DoD-IL5 microservice, a HIPAA-covered persistence layer, etc.) becomes
a **typed overlay-set declaration** that *generates* the values fragment
for the consumer chart.

```yaml
# in a hypothetical ./use-cases/dod-il5-microservice.yaml
overlay-set: dod-il5-microservice
overlays:
  - fedramp-high
  - airgap
  - supplychain
  - fips
  - dod-il5
defaults:
  compliance:
    fips:
      runtime: go-boringcrypto
    supplychain:
      slsa:
        level: 3
    dod:
      impactLevel: il5
```

A consumer chart imports the overlay-set:

```yaml
# in their values.yaml
extends: dod-il5-microservice    # processed by a build-time generator,
                                  # NOT helm itself

# only the workload-specific stuff:
image:
  repository: zot.registry.svc.cluster.local/my-team/my-service
  tag: "sha256:..."
replicaCount: 3
```

The generator (a tatara-lisp `defprogram`, or a small Rust CLI) expands
`extends:` into the full values set at chart-build time, with the
overlay closure already computed. The consumer never sees the 100-line
compliance values — just the workload-specific fields.

This is the *typed overlay-set as a primitive* layer the user asked
for. It compounds because:

- A new use-case is one overlay-set declaration: `dod-il6-microservice`,
  `hipaa-database`, `pci-dss-payment-gateway`, …
- Each declaration is provably correct: the overlays it composes are
  individually proven, the composition rule is one function, the
  generator just emits the fragment.
- The proof for a new use-case is "this overlay-set is the union of
  these proven overlays" — no per-use-case proof work needed.

---

## 6. Migration plan from the current shape

### Phase A — preparation (zero risk)

1. Add the overlay registry shape to `pleme-lib` 0.9.0 alongside the
   existing scattered helpers — both work in parallel.
2. Convert each existing `_compliance_<concern>.tpl` to also declare a
   `pleme-lib.overlay.<concern>` shape, calling its existing
   sub-helpers internally. Backward-compat preserved.

### Phase B — opt-in migration

3. Document `compliance.overlays: [...]` as the new way to declare.
4. Existing `compliance.baseline / .airgap / .supplychain / .fips`
   values continue to work; if `overlays` is set, they're ignored in
   favor of the explicit list.

### Phase C — generator + use-case library

5. Build the small Rust CLI (`pleme-compliance-gen` or extension to
   `forge`) that reads an overlay-set declaration and emits the values
   fragment. Ship `./use-cases/*.yaml` as the canonical library.
6. Migrate top consumer charts (pleme-microservice, pleme-zot,
   pleme-image-sync) to use the generator pattern.

### Phase D — deprecate the scatter

7. After ≥1 release with both shapes coexisting and consumer charts
   migrated, deprecate the scattered values shape. The internal helper
   files stay (overlays implement them); only the values surface
   collapses.

---

## 7. The control-coverage table becomes mechanical

Today: the control-coverage table in `COMPLIANCE-PROOF.md` is a
hand-maintained Markdown table. Adding a new control means manually
editing the table and hoping every related test still asserts the
right thing.

With overlays: the table is generated from the registry. A small
Rust CLI walks every `pleme-lib.overlay.*` template, extracts its
`controls` declaration, and emits:

- The per-overlay control list
- The per-overlay validator-to-control map
- The per-overlay test-corpus index

CI compares the generated table against the checked-in
`COMPLIANCE-PROOF.md`; drift fails the build. The proof is now
*physically synchronized* with the implementation, not maintained by
hand.

---

## 8. What this enables in 12 months

- **HIPAA overlay** — covers HIPAA Security Rule §164.308 / §164.310 /
  §164.312. Twelve hours of work to write + test the overlay; every
  consumer chart can opt into HIPAA by adding `hipaa` to its overlays.
- **PCI-DSS overlay** — covers PCI-DSS v4.0 control list. Same pattern.
- **CMMC L3 overlay** — covers CMMC Level 3 controls. Composes with
  fedramp-high + airgap + supplychain.
- **EU NIS2 overlay** — covers NIS2 Directive Article 21. Composes
  differently (EU residency, GDPR-aware secret handling).
- **BSI C5 overlay**, **ISO 27001 Annex A overlay**, etc.

Each new regime is one `_overlay_<name>.tpl` file + one tests file +
one entry in `COMPLIANCE-PROOF.md`. Adding a regime can't break the
others because the composition rule is a typed function, not
hand-edited boolean spaghetti.

---

## 9. Why now, vs continuing the scatter pattern

The scatter pattern works for the first 5–10 concerns. We have ~13.
The Wave 4 regression today (one nil-deref, one bypass) was a symptom
of the scatter limit being reached. The next regime adds another file,
another `validate` chain entry, another control-list conditional —
each touch risks another regression.

The overlay refactor is ~1 day of focused work. After it, every new
regime is hours instead of days, with provability included.

---

## 10. Decision

This document proposes the migration. **Recommendation: proceed in the
phased manner above (A → B → C → D), starting with Phase A in
`pleme-lib` 0.9.0** as a non-breaking parallel implementation. Existing
consumer charts and tests stay green throughout migration; the proof
shape strengthens (gains the mechanical control-coverage generation)
without disrupting the workload-author experience.

Once Phase A lands and stabilizes, Phase B can roll out per-chart at
each chart's natural release cadence; Phase C is a parallel-track
generator effort; Phase D is the cleanup ≥6 months after Phase A.

The work scope:
- Phase A: ~1 day (refactor 13 helpers into the dual shape, add registry
  + dispatch, write the design tests).
- Phase B: per-chart cost ~1 hour (mostly mechanical values rewrite).
- Phase C: ~3 days (Rust CLI + 5 canonical use-case declarations).
- Phase D: ~1 hour per chart (cleanup).
