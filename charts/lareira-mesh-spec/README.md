# lareira-mesh-spec

Per-Aplicacao mesh declaration. Renders the typed `(defmesh …)`
surface to its concrete K8s manifests.

## What it renders

Per HelmRelease (= one logical mesh):

| Resource | Count | What |
|---|---|---|
| `ClusterSPIFFEID` | 1 per Servico + 1 per participant | SPIRE-controller-manager issues SVIDs against these |
| `ConfigMap` (aresta-config) | 1 per participating namespace | The aresta sidecar mounts `/etc/aresta/config.yaml` |
| `ClusterRoleBinding` | 1 per participating namespace | Binds `system:serviceaccounts:<ns>` to the cluster-singleton resolver ClusterRole |
| `NetworkPolicy` | 1 per participating namespace | Open ingress on every meshed pod (mesh authn = SPIFFE-ID is the trust boundary) |
| `ServiceAccount` | 1 per `createServiceAccount: true` entry | Fallback for charts that don't emit one |

## Quick install

```bash
helm install openclaw-mesh oci://ghcr.io/pleme-io/charts/lareira-mesh-spec \
  --version "*" \
  --namespace mesh-system \
  -f my-mesh-values.yaml
```

Requires:
- [`lareira-aresta-defaults`](../lareira-aresta-defaults/) installed (provides the cluster-singleton resolver ClusterRole)
- [`lareira-enxerto`](../lareira-enxerto/) installed (the sidecar-injection webhook)
- SPIRE running (helm-charts-hardened)

## Values shape

```yaml
mesh:
  name: openclaw-mesh
  trustDomain: pleme.io
  namespace: openclaw

spire:
  className: spire-system-spire

resolverClusterRole: aresta-resolver

servicos:
  - name: cartorio
    serviceAccount: openclaw-stack-cartorio
    podSelector:
      app.kubernetes.io/instance: openclaw-stack
      app.kubernetes.io/name: cartorio
  # ...

participants:
  - name: cloudflared
    namespace: cloudflared
    serviceAccount: cloudflared
    createServiceAccount: true
    podSelector:
      app: cloudflared

arestaConfig:
  inboundAddr:  "0.0.0.0:15001"
  outboundAddr: "0.0.0.0:15006"
  probeAddr:    "0.0.0.0:4191"
  # ...

networkPolicy:
  enabled: true
```

See `examples/openclaw-mesh.yaml` for the full pleme-dev shape.

## SPIFFE-ID derivation

Each Servico/participant maps to:

```
spiffe://<trustDomain>/ns/<namespace>/sa/<serviceAccount>
```

The aggregated allowlist (peer + upstream) is the cartesian product
of every Servico × `mesh.namespace` plus every participant ×
`participant.namespace`. Both directions get the same list — coarse
trust within the Aplicacao boundary.

For finer-grained per-edge contracts (e.g. `cartorio :para lacre :on
8083`), see the typed `(defmesh …)` `:contratos` surface in
[`pleme-io/tatara-mesh`](https://github.com/pleme-io/tatara-mesh)
(M4+ work).

## Multi-mesh isolation

The chart prefixes every CR name with `mesh.name`. Two mesh-spec
HelmReleases in the same cluster never collide:

```yaml
# mesh A
mesh: { name: openclaw-mesh, namespace: openclaw }
# →  ClusterSPIFFEID/openclaw-mesh-cartorio

# mesh B
mesh: { name: lilitu-mesh, namespace: lilitu }
# →  ClusterSPIFFEID/lilitu-mesh-bff
```

The aresta-config CM is also `<mesh.name>-aresta-config` so the
enxerto admission's per-pod annotation
`enxerto.mesh.pleme.io/aresta-config-cm` selects the right one.

## Testing

```bash
helm unittest -f "tests/lareira-mesh-spec/*_test.yaml" charts/lareira-mesh-spec
```

37 specs covering: SPIFFE-ID rendering, allowlist aggregation,
per-participant CM copies, RBAC binding shape, NetworkPolicy
generation, missing-SA fallback, multi-namespace deduplication, trust
domain plumbing, outbound/probe address overrides.
