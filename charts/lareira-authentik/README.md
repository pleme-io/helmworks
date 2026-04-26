# lareira-authentik chart

Breathable Authentik for the rio cluster (and any pleme-io home-edge
cluster offering SSO).

Wraps the upstream `goauthentik/authentik` chart with pleme-io
conventions:

- **Breathable server tier** — KEDA HTTP add-on scales the Authentik
  server 0→1 on inbound auth request. Cold start ~15s; cooldownPeriod
  600s (kept warm 10 min after last request). Worker stays at 1 for
  scheduled tasks.
- **Always-on state tier** — PostgreSQL + Redis bundled as subcharts,
  PVC-backed, elastic-storage tier (the `pleme-storage-elastic`
  watcher resizes them at 80% utilization).
- **Outpost (always-on, tiny)** — the embedded outpost Deployment is
  what ingress-nginx forward-auth and Cloudflare Zero Trust talk to.
  ~50 MiB resident.
- **ServiceMonitor + PrometheusRule** — vmagent scrapes Authentik
  server metrics; vmalert routes the canonical alerts (server down,
  cold-start churn) through the rio alertmanager-ntfy severity tree.

## Architecture (rio + quero.cloud)

```
                  ┌────────────────────────────────────────────┐
internet user  ─► │ Cloudflare Zero Trust Access (edge SSO)    │  ← always on (Cloudflare-side)
                  │   email-OTP (default) | OIDC → Authentik   │
                  └──────────────────┬─────────────────────────┘
                                     │ Cloudflare Tunnel
                                     ▼
                  ┌────────────────────────────────────────────┐
                  │ ingress-nginx (LAN-side) │ cloudflared     │  ← always on (tiny)
                  └──────────────────┬─────────────────────────┘
                                     │ auth_request to outpost
                                     ▼
                  ┌────────────────────────────────────────────┐
                  │ authentik-outpost (always on, ~50 MiB)     │  ← always on (tiny)
                  └──────────────────┬─────────────────────────┘
                                     │ OIDC flow
                                     ▼
                  ┌────────────────────────────────────────────┐
                  │ authentik-server (KEDA: 0..N pods)          │  ← scale 0→1→0
                  │   cold start ~15s on first request          │
                  └──────────────────┬─────────────────────────┘
                                     │
              ┌──────────────────────┼─────────────────────┐
              ▼                      ▼                     ▼
       ┌────────────┐        ┌────────────┐        ┌────────────┐
       │ PostgreSQL │        │ Redis       │        │ vmsingle    │
       │ (always on)│        │ (always on) │        │ (always on) │
       └────────────┘        └────────────┘        └────────────┘
```

## Defense in depth: Cloudflare ZT + Authentik

Two-layer SSO:

1. **Cloudflare Zero Trust Access** — runs at Cloudflare's edge,
   intercepts every request to `*.quero.cloud` apps before it
   reaches rio. Email-OTP by default; federates to Authentik OIDC
   when configured.

2. **Authentik in-cluster** — issues OIDC tokens that Cloudflare
   ZT consumes. Independent identity store. Even if a CF Access
   policy misconfigures, Authentik still refuses unauthorized
   token requests.

Authentik is itself NOT gated by CF ZT (it would create a chicken-
and-egg loop). It's exposed via Cloudflare Tunnel directly at
`auth.quero.cloud` — TLS-terminated, but no CF Access challenge.

## Installing

```sh
helm dep up charts/lareira-authentik
helm install authentik ./charts/lareira-authentik \
  --namespace authentik \
  --create-namespace \
  --set enabled=true \
  -f ~/.config/lareira-authentik/secrets.yaml   # holds authentik.secret_key etc.
```

KEDA + the KEDA HTTP add-on must be installed in the cluster.

## Default-OFF

`enabled: false` is the default. Helm renders nothing until the
operator opts in. The cluster's authentik footprint is zero until
the chart is enabled.

## Pillar 11 alignment

- Server is breathable (Pillar 11 — JIT Infrastructure).
- ServiceMonitor + PrometheusRule wired by default (Pillar 11 —
  mandatory alert layer).
- Helm-first authoring (theory/BREATHABILITY.md §VII.7) — wraps
  upstream, no raw HelmRelease in the FluxCD tree.

## Replacing the raw HelmRelease

The current `clusters/rio/infrastructure/authentik/release.yaml` is a
raw `HelmRelease` block with values inline. It violates the
helm-first invariant from `BREATHABILITY.md §VII.7`. Migration:

```yaml
# clusters/rio/infrastructure/authentik/release.yaml — NEW shape
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: lareira-authentik
  namespace: authentik
spec:
  interval: 30m
  suspend: true                         # default-off until rollout day
  chart:
    spec:
      chart: lareira-authentik
      version: "0.1.x"
      sourceRef:
        kind: HelmRepository
        name: pleme-charts               # the helmworks GHCR OCI repo
        namespace: flux-system
  values:
    enabled: true                        # rio opts in by flipping this
    # rio-specific overrides only — most defaults work as-is.
    cloudflared:
      hostname: auth.quero.cloud
```

Resulting tree: ~10 lines of rio-specific values vs the current ~75
lines of inline upstream config.

## See also

- [theory/BREATHABILITY.md §II](../../../theory/BREATHABILITY.md) — listener tier vs on-demand work tier vs state tier.
- [theory/BREATHABILITY.md §VII.7](../../../theory/BREATHABILITY.md) — helm-first authoring invariant.
- [pangea-architectures CloudflareZeroTrustAccess](../../../pangea-architectures/lib/pangea/architectures/cloudflare_zero_trust_access.rb) — edge SSO architecture (Pangea-rendered, applied by Terraform).
- [Authentik upstream chart](https://artifacthub.io/packages/helm/goauthentik/authentik) — what we wrap.
