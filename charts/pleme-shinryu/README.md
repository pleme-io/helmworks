# pleme-shinryu

DataFusion analytical query plane for Shinryū observability data. Deploys
shinryu-mcp as a K8s service with shared PVC for Vector analytics output.

## Prerequisites

- `pleme-vector` deployed with `sink.analytics.enabled: true`
- Shared PVC for Bronze/Silver/Gold data (created by this chart)
- KEDA operator (optional, for breathing mode)

## Deploy

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: shinryu-mcp
  namespace: observability
spec:
  chart:
    spec:
      chart: pleme-shinryu
      version: "0.1.0"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts
  values:
    analytics:
      pvc:
        claimName: shinryu-analytics
        size: 100Gi
```

## Data Contract (Vector ↔ shinryu)

```
Shared PVC:
  bronze/  ← Vector writes NDJSON (30s batches)
  silver/  ← shinryu writes Parquet (1-min refiner)
  gold/    ← shinryu writes views (5-min materializer)
```

## Breathing Mode

Scale to zero when idle, wake on NATS events:

```yaml
breathing:
  enabled: true
  min_replicas: 0
  max_replicas: 3
  sleep_after_secs: 900
```

## Values

| Key | Default | Description |
|-----|---------|-------------|
| `analytics.path` | `/var/lib/vector/analytics` | Data root |
| `analytics.pvc.size` | `100Gi` | PVC size |
| `datafusion.memory_limit_mb` | `1024` | DataFusion memory |
| `refiner.enabled` | `true` | Bronze→Silver |
| `materializer.enabled` | `true` | Silver→Gold |
| `lifecycle.bronze_retention_days` | `7` | Bronze TTL |
| `lifecycle.silver_retention_days` | `30` | Silver TTL |
| `udfs.burst_forge` | `true` | Domain-specific UDFs |
