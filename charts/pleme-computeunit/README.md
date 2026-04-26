# pleme-computeunit

Library chart for deploying a tatara-lisp program (or any WASM/WASI
module) as a `ComputeUnit` on the
[`lareira-wasm-platform`](../lareira-wasm-platform/) runtime.

The Helm-first analog of the loose `kubectl apply -f computeunit.yaml`
shape — required by
[`theory/BREATHABILITY.md` §VII.7](https://github.com/pleme-io/theory/blob/main/BREATHABILITY.md)
which mandates that every in-cluster workload goes through Helm.

## What it emits

Per-shape sidecar resources auto-rendered from `trigger.<shape>`:

| Shape | Resources rendered |
|---|---|
| **program** (one-shot) | ComputeUnit only |
| **job** (cron) | ComputeUnit only — operator handles scheduling |
| **service** (HTTP) | ComputeUnit + Service + (optional) HTTPScaledObject + (optional) ServiceMonitor |
| **function** (event) | ComputeUnit + KEDA ScaledObject (NATS / Kafka / SQS / Redis / RabbitMQ) |
| **controller** (CR-watch) | ComputeUnit + (optional) policy CR |

Plus optional `PrometheusRule` for any shape — consumer-supplied rules.

## Shape detection

The chart inspects `Values.trigger` — exactly one of `oneShot`, `cron`,
`service`, `event`, `watch` must be set, and the helper
`pleme-computeunit.shape` returns the matching name. Setting zero or
multiple is a render-time error (no silent default).

## Consumer-chart pattern

```yaml
# helmworks/charts/lareira-pvc-autoresizer/Chart.yaml
apiVersion: v2
name: lareira-pvc-autoresizer
description: PVC autosize watcher — reuses pleme-storage-elastic logic as a tatara-lisp ComputeUnit
type: application
version: 0.1.0
appVersion: "0.1.0"
dependencies:
  - name: pleme-computeunit
    version: "~0.1.0"
    repository: "file://../pleme-computeunit"
```

```yaml
# helmworks/charts/lareira-pvc-autoresizer/values.yaml
pleme-computeunit:
  enabled: false
  module:
    source: "github:pleme-io/programs/pvc-autoresizer/main.tlisp?ref=v0.1.0"
  trigger:
    cron: "*/5 * * * *"
  capabilities:
    - kube-pvc-list
    - kube-pvc-patch
    - prom-query@vmsingle-vm.monitoring.svc:8429
  config:
    triggerAt: 0.80
    expandFactor: 1.25
    maxSize: "100Gi"
```

A consumer chart is ~30 lines total — a Chart.yaml plus the values
override block.

## Why a library chart, not an umbrella

Library charts (`type: library`) emit no resources of their own; they
provide templates that consumer charts include. This makes per-program
charts trivial: each consumer sets its values and inherits all the
shape detection, validation, and observability wiring for free.

## See also

- [theory/BREATHABILITY.md §VII.7](https://github.com/pleme-io/theory/blob/main/BREATHABILITY.md) — the helm-first invariant
- [theory/WASM-STACK.md](https://github.com/pleme-io/theory/blob/main/WASM-STACK.md) — the runtime
- [theory/WASM-PACKAGING.md](https://github.com/pleme-io/theory/blob/main/WASM-PACKAGING.md) — module URL grammar
- [`lareira-wasm-platform`](../lareira-wasm-platform/) — the operator
- [`lareira-pvc-autoresizer`](../lareira-pvc-autoresizer/) — first consumer
