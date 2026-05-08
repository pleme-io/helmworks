# lareira-aresta-defaults

Cluster-singleton prerequisites for the
[aresta](https://github.com/pleme-io/aresta) sidecar:

- the `aresta-resolver` ClusterRole (read-only on Services + EndpointSlices)
- a cluster-wide PodMonitor scraping every meshed pod's `mesh-metrics`
  port (9090)
- a PrometheusRule with mesh-health alerts

Per-mesh `ClusterRoleBinding`s live in
[`lareira-mesh-spec`](../lareira-mesh-spec/) — bindings are per-mesh,
the role itself is shared.

## Quick install

```bash
helm install aresta-defaults oci://ghcr.io/pleme-io/charts/lareira-aresta-defaults \
  --version "*" \
  --namespace mesh-system
```

## Key values

| Key | Default | Purpose |
|---|---|---|
| `clusterRoleName` | `aresta-resolver` | Stable name; mesh-spec bindings reference it. |
| `podMonitor.enabled` | `true` | Toggle off when the cluster has no prometheus-operator CRDs. |
| `prometheusRule.enabled` | `true` | Toggle off when prometheus-operator CRDs absent. |
| `prometheusRule.alerts` | 3 stock alerts | TLS failures, breaker open, connect failures. Operator-tunable. |

## Stock alerts

| Alert | Condition | Severity |
|---|---|---|
| `ArestaTLSFailuresHigh` | `rate(aresta_outbound_tls_failures_total[5m]) > 0.1` for 5m | warning |
| `ArestaCircuitBreakerOpen` | `increase(aresta_outbound_circuit_breaker_open_total[5m]) > 0` for 1m | warning |
| `ArestaConnectFailuresHigh` | `rate(aresta_outbound_connect_failures_total[5m]) > 0.5` for 5m | warning |

## Testing

```bash
helm unittest -f "tests/lareira-aresta-defaults/*_test.yaml" charts/lareira-aresta-defaults
```

12 specs covering: ClusterRole rules shape, PodMonitor cluster-wide
selector, alert rule names + thresholds, disable toggles.
