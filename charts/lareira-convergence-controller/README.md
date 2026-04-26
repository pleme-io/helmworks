# lareira-convergence-controller

The platform's own convergence controller, packaged as a Helm chart
that deploys a tatara-lisp program. Closes the recursive bootstrap
loop:
[`theory/WASM-RUNTIME-COMPLETE.md` §IV](https://github.com/pleme-io/theory/blob/main/WASM-RUNTIME-COMPLETE.md).

## Migration phasing

This chart is **NOT yet a drop-in replacement** for the existing
[`tatara/tatara-reconciler`](https://github.com/pleme-io/tatara/tree/main/tatara-reconciler).
It runs side-by-side under the migration phasing from
[`WASM-RUNTIME-COMPLETE.md` §III.2](https://github.com/pleme-io/theory/blob/main/WASM-RUNTIME-COMPLETE.md):

| Phase | Status | Action |
|---|---|---|
| α | now | This chart reviewed but not deployed |
| β | TBD | Rust `tatara-reconciler` accepts `Process.spec.runtime: rust\|lisp`; this chart deployed alongside; operators opt in per CR |
| γ | TBD | After ~30 days of parity, default `Process.spec.runtime: lisp` |
| δ | TBD | Deprecate the Rust controller; this chart becomes canonical |

## Why ship the chart now

Even pre-deployment, the chart serves as:
- The reference for the meta-framework (`theory/META-FRAMEWORK.md`) —
  shows that the platform's own controller fits the same
  `pleme-computeunit` shape as every program.
- The phase-α review artifact for operators evaluating the migration.
- The deployment surface that's ready when phase β kicks off — no
  chart authoring will gate phase β.

## See also

- [`pleme-computeunit`](../pleme-computeunit/) — library chart
- [`pleme-io/programs/convergence-controller`](https://github.com/pleme-io/programs/tree/main/convergence-controller) — the source
- [`theory/WASM-RUNTIME-COMPLETE.md`](https://github.com/pleme-io/theory/blob/main/WASM-RUNTIME-COMPLETE.md) — the recursive-bootstrap design
