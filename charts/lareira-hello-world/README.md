# lareira-hello-world

The canonical pleme-io WASM/WASI breathable service. Hello, world.

Demonstrates **every architectural commitment** in one place:

| Commitment | How |
|---|---|
| Tatara-lisp authoring | `main.tlisp` ~70 lines |
| WASM/WASI runtime | wasm-operator dispatches the engine pod |
| Capability-bounded | `http-in` + `kube-downward-api` only |
| Breathable | KEDA HTTP, `minReplicas=0`, cooldown 10min |
| URL-addressable | `github:pleme-io/programs/hello-world/main.tlisp?ref=v0.1.0` |
| Helm-first | this chart + `pleme-computeunit` library |
| Default-OFF | `enabled: false` until operator opts in |
| Observable by default | ServiceMonitor + 3 PrometheusRule alerts |
| YAML-on-top config | `spec.config.greeting / audience / punctuation` editable per-cluster |

## Install

```sh
helm install hello-world ./charts/lareira-hello-world \
  --namespace tatara-system --create-namespace \
  --set 'pleme-computeunit.enabled=true'
```

Or via FluxCD per
[`theory/FLEET-DECLARATION.md`](https://github.com/pleme-io/theory/blob/main/FLEET-DECLARATION.md)
by adding to the cluster's `programs/release.yaml` programs list.

## Test

```sh
curl https://hello.quero.cloud/hello
# → {"message":"Hello, world!","served-by":"hello-world-7d8f-abc"}

curl https://hello.quero.cloud/hello/drzzln
# → {"message":"Hello, drzzln!","served-by":"hello-world-7d8f-abc"}

curl https://hello.quero.cloud/healthz
# → {"status":"ok","pod":"...","namespace":"tatara-system","cluster":"rio"}
```

## Customize

Override the greeting per-cluster:

```yaml
pleme-computeunit:
  config:
    greeting: "Howdy"
    audience: "partner"
    debug: true
```

No WASM rebuild. The CR change propagates via FluxCD; the engine
pod restarts with new config.

## Cost model

| State | Resident |
|---|---|
| Idle (no requests for 10 min) | 0 pods, 0 MiB |
| One request | 1 pod, ~50 MiB resident, ~3s cold start |
| 100 RPS | up to 5 pods (maxReplicas), drains within 10 min |
| Burst | KEDA scales up to 5; settles back down |

## See also

- [`pleme-io/programs/hello-world`](https://github.com/pleme-io/programs/tree/main/hello-world) — source
- [`pleme-computeunit`](../pleme-computeunit/) — library chart
- [`theory/META-FRAMEWORK.md`](https://github.com/pleme-io/theory/blob/main/META-FRAMEWORK.md) — the meta-framework hello-world exemplifies
