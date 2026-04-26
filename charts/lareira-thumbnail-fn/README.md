# lareira-thumbnail-fn

Event-driven thumbnail generator. Demonstrates the **function shape**
formalized in
[`theory/WASM-PACKAGING.md` §IV.1](https://github.com/pleme-io/theory/blob/main/WASM-PACKAGING.md)
— AWS-Lambda-async-style invocation but running in your own cluster
with cold-start ~3s vs ~30s for container Lambdas.

## How it scales

```
NATS subject empty   → 0 wasm-engine pods, $0 cost
First event arrives  → engine pod boots in ~3s, processes batch, exits
100 events arrive    → KEDA dispatches in batches of 10; up to 20 parallel pods
60s idle             → next event boots cold again
```

Lag-growing alert (`>100 pending for 5m`) catches situations where
the function can't keep up with upload rate — operators can raise
`maxReplicas` or investigate why pods aren't scaling.

## See also

- [`pleme-computeunit`](../pleme-computeunit/) — library chart
- [`theory/WASM-PACKAGING.md` §IV.1](https://github.com/pleme-io/theory/blob/main/WASM-PACKAGING.md) — function shape
