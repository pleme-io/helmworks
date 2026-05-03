# lareira-tatara-stack

Helm umbrella for the WASM/WASI runtime stack on pleme-io clusters.

**Anchored by [`lareira-wasm-platform`](../lareira-wasm-platform/)**
(required). Adds [`lareira-tatara-runtime`](../lareira-tatara-runtime/)
and [`lareira-openclaw`](../lareira-openclaw/) as **optional sugar**
layers — both default OFF.

## What you can run

The runtime hosts four shapes — same `ComputeUnit` CR for each, just
a different `spec.trigger`:

| Shape | trigger | Use |
|---|---|---|
| program | `oneShot` | one-shot CLI-style work |
| job | `cron: "..."` | periodic batch (the `pvc-autoresizer` shape) |
| service | `service: { port, hosts }` | long-running HTTP/gRPC, scale-to-zero via KEDA HTTP |
| controller | `watch: { group, kind }` | CRD reconciler — author K8s operators as WASM modules |

See [`theory/WASM-STACK.md`](../../../theory/WASM-STACK.md) for the
full design + examples per shape.

## Authoring paths

WASM modules can be authored in any language that compiles to
`wasm32-wasi`. First-class paths in pleme-io:

- **tatara-lisp** (typed Lisp; composes pleme-io domains for free) →
  optionally pair with `lareira-tatara-runtime` for auto-compile + auto-submit.
- **Rust** + `kube-rs` + `wit-bindgen` + `cargo-component`.
- **Go** + TinyGo + WASI.
- **Python** + `componentize-py`.

## Install

```sh
# Minimum: just the runtime.
helm install wasm ./charts/lareira-tatara-stack \
  --namespace tatara-system --create-namespace \
  --set enabled=true \
  --set wasmPlatform.enabled=true

# With tatara-lisp evaluator + openclaw attestation cache:
helm install wasm ./charts/lareira-tatara-stack \
  --namespace tatara-system --create-namespace \
  --set enabled=true \
  --set wasmPlatform.enabled=true \
  --set tataraRuntime.enabled=true \
  --set openclaw.enabled=true
```

Or via FluxCD:

```yaml
# clusters/<name>/infrastructure/wasm-stack/release.yaml
spec:
  values:
    enabled: true
    wasmPlatform:  { enabled: true }
    tataraRuntime: { enabled: false }    # opt in when ready
    openclaw:      { enabled: false }
```

## Default-OFF

Like every chart in this fleet (per
[BREATHABILITY.md §VII.7](../../../theory/BREATHABILITY.md)),
the umbrella renders nothing until `enabled: true`. Each peer
chart follows the same default.

## Phase A status (this scaffold)

- ✅ `lareira-wasm-platform` (operator + engine + store + RBAC + ServiceMonitor + alerts)
- ✅ `lareira-openclaw` (Deployment + Service + SQLite/Postgres backend) — optional
- ✅ `lareira-tatara-runtime` (lisp evaluator, auto-submit) — optional
- ✅ `lareira-tatara-stack` (umbrella — this chart)

## Phase B (action items)

The chart references images that need to be built + published to
`ghcr.io/pleme-io` before the chart can deploy:

| Image | Source repo | Build |
|---|---|---|
| `ghcr.io/pleme-io/wasm-operator:0.1.0` | [wasm-platform](https://github.com/pleme-io/wasm-platform) | add `image` attribute to its flake |
| `ghcr.io/pleme-io/wasm-engine:0.1.0`   | [wasm-platform](https://github.com/pleme-io/wasm-platform) | add `image` attribute to its flake |
| `ghcr.io/pleme-io/cartorio:0.1.0` | [cartorio](https://github.com/pleme-io/cartorio) | add `image` attribute to its flake (optional) |
| `ghcr.io/pleme-io/tatara-lisp-script:0.1.0` | [tatara-lisp](https://github.com/pleme-io/tatara-lisp) | add `image` attribute to its flake (optional) |

## See also

- [theory/WASM-STACK.md](../../../theory/WASM-STACK.md) — the runtime design (4 shapes, capabilities, breathability)
- [theory/SCRIPTING.md](../../../theory/SCRIPTING.md) — tatara-lisp as authoring layer
- [theory/BREATHABILITY.md](../../../theory/BREATHABILITY.md) — fleet-wide use-causes-spin-up
- Upstream: [`wasm-platform`](https://github.com/pleme-io/wasm-platform), [`tatara-lisp`](https://github.com/pleme-io/tatara-lisp), [`cartorio`](https://github.com/pleme-io/cartorio)
