# lareira-respiro

**respiro** — the packaged NATS-JetStream-scale-to-zero + breathability
**"breathing pipeline"** primitive. *respiro* is Portuguese for *breath*: the
pipeline inhales events on demand (scale-from-zero), holds them at a utilization
band (breathe 80/20 homeostasis), and exhales to a terminal sink.

This chart **composes already-shipped `pleme-lib` helpers** — it owns **no new
scaling / transport / homeostasis algebra**. The only net-new code surface is one
typed `pleme-lib` emitter (`pleme-lib.vectorConfig`); everything else is wiring.

## The 5-stage spine

Each stage maps 1:1 onto a `pleme-lib` named template:

| # | Stage | What | `pleme-lib` helper |
|---|-------|------|--------------------|
| 1 | **INGEST** | a Vector Deployment + ConfigMap + Service + SA; config rendered from typed values | `pleme-lib.vectorConfig` (NEW) |
| 2 | **TRANSPORT + BUFFER** | a JetStream workqueue stream + pull consumer (ConfigMap + init Job) | `pleme-lib.jetstream` |
| 3 | **WAKE** | the consumer Deployment + Service + a KEDA ScaledObject scaling 0→N on stream lag | `pleme-lib.breathability` |
| 4 | **HOLD** | breathe MemoryBand / CpuBand carving the consumer's limits at the setpoint, SHADOW-first | `pleme-lib.breatheBand` |
| 5 | **SINK** | terminal egress (vlogs \| nats) + delivery-guarantee semantics | `pleme-lib.delivery` |
| + | **OBSERVE** | ServiceMonitor + PrometheusRule + AlertmanagerConfig attached to the consumer | lareira-observe ATTACH shape |

```
events ─▶ (1) Vector ─▶ (2) JetStream workqueue ─▶ (3) KEDA 0→N ─▶ consumer ─▶ (5) sink
                                                          │
                                                   (4) breathe band holds it at setpoint
                                                          │
                                                   (+) scrape + alerts
```

## The one net-new surface — `pleme-lib.vectorConfig`

A typed Vector-config emitter (`charts/pleme-lib/templates/_vector_config.tpl`).
It builds the Vector config as a **Helm dict** and serializes it with a **single
`toYaml`** — ★★ TYPED EMISSION: there is **no string-concatenation of config
syntax**. Adding a source/sink kind is adding a typed arm to the dict, never a
`printf`.

A0 sources: `kubernetes_logs | http | socket`. The `s3` source is a later
milestone — a typed slot that `fail()`s with a clear message rather than emitting
a silently-wrong config. The terminal Vector sink is always `nats` (the transport
hand-off into JetStream).

## Default-off

`respiro.enabled=false` (the default) renders **zero documents** — a HelmRelease
shipped before its values are wired is a safe no-op (keeps auto-release green).
Flip `respiro.enabled=true` in the HelmRelease values to deploy. Each stage has
its own independent toggle (`ingest.enabled`, `breathe.enabled`,
`observe.monitoring.enabled`, `sink.kind`, …).

## Minimum values

```yaml
respiro:
  enabled: true
  ingest:
    source:
      kind: kubernetes_logs      # | http | socket   (s3 = later milestone)
  stream:
    name: AUDIT
    subjects: [audit.>]
    consumer: { name: respiro, maxAckPending: 1 }   # maxAckPending=1 = serialized
  serverUrl: nats://pleme-nats.nats.svc:4222
  consumers:
    image: { repository: ghcr.io/pleme-io/respiro-consumer, tag: "..." }
    min: 0
    max: 8
    lagThreshold: 100
  breathe:
    enabled: true
    dryRun: true               # SHADOW-first — observe before carving
    memory: { enabled: true, floor: 256Mi, ceiling: 2Gi }
  sink:
    kind: vlogs                # | nats   (vm|grafana|splunk|coralogix|datadog = later)
    vlogs: { endpoint: http://victoria-logs.monitoring.svc:9428 }
```

See `values.yaml` for the full typed contract.

## Later-milestone slots (declared, not yet emitted)

- **INGEST source** `s3` — a typed slot in `pleme-lib.vectorConfig` that `fail()`s.
- **SINK** `vm | grafana | splunk | coralogix | datadog` — `sink.kind` `fail()`s on
  any kind other than `vlogs | nats` in A0. The values surface enumerates them for
  the verification matrix.

## Testing

```bash
cd charts/lareira-respiro
helm dependency build .
helm unittest -f "../../tests/lareira-respiro/*_test.yaml" .
# or: nix run .#"stack:unittest"
```

The suite proves: default-off → 0 documents; each stage toggle independently;
the source.kind × sink.kind matrix subset (kubernetes_logs|http|socket ×
vlogs|nats); the later-milestone `fail()` slots; and a full-on snapshot.
