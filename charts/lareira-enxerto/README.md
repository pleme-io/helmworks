# lareira-enxerto

Cluster-singleton MutatingAdmissionWebhook that grafts the
[aresta](https://github.com/pleme-io/aresta) sidecar into pods
labeled `mesh.pleme.io/inject=true`.

## Quick install

```bash
helm install enxerto oci://ghcr.io/pleme-io/charts/lareira-enxerto \
  --version "*" \
  --namespace mesh-system --create-namespace \
  --set webhook.caBundle="$(base64 < ca.crt)"
```

The matching TLS Secret (`enxerto-webhook-tls`) must contain
`tls.crt` + `tls.key` signed against `enxerto.<namespace>.svc`.

## With cert-manager (recommended for production)

```yaml
webhook:
  certManager:
    enabled: true
    issuerKind: ClusterIssuer
    issuerName: cluster-ca
```

cert-manager owns the Secret + auto-rotates the MWC's caBundle via
`cert-manager.io/inject-ca-from`.

## Companion charts

| Chart | Role |
|---|---|
| `lareira-aresta-defaults` | Cluster-singleton resolver ClusterRole + PodMonitor + PrometheusRule. Install once per cluster. |
| `lareira-mesh-spec` | Per-Aplicacao mesh declaration. ClusterSPIFFEIDs, peer/upstream allowlists, RBAC bindings. |

The complete mesh = `enxerto` + `aresta-defaults` + one or more
`mesh-spec` HelmReleases. See `helmworks/usecases/mesh/`.

## Key values

| Key | Default | Purpose |
|---|---|---|
| `image.tag` | `amd64-92750c5` | enxerto binary SHA-pin |
| `arestaImage` | `ghcr.io/pleme-io/aresta:amd64-6a8a463` | aresta sidecar SHA-pin (overridable per cluster) |
| `meshOutboundCidrs` | `[10.42.0.0/16, 10.43.0.0/16]` | CNI pod + service CIDRs whose outbound TCP gets aresta-out REDIRECTed |
| `webhook.failurePolicy` | `Ignore` | `Fail` once cluster is stable + redundant replicas exist |
| `webhook.excludeNamespaces` | `[kube-system, flux-system, spire-system]` | Per-cluster opt-out list |
| `webhook.certManager.enabled` | `false` | When true, no operator-managed caBundle needed |

## Testing

```bash
( cd charts/lareira-enxerto && helm dep update )
helm unittest -f "tests/lareira-enxerto/*_test.yaml" charts/lareira-enxerto
```

24 specs covering: image pin, env vars, port mapping, TLS volume
mounts, MWC selector + namespace exclusions, caBundle injection vs
cert-manager-mode, fullnameOverride preservation.

## See also

- [`pleme-io/enxerto`](https://github.com/pleme-io/enxerto) — the binary
- [`pleme-io/aresta`](https://github.com/pleme-io/aresta) — the sidecar
- `MESH-STATUS.md` in [`pleme-io/aresta`](https://github.com/pleme-io/aresta) — current data-plane state
