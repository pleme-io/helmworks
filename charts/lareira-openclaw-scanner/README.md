# lareira-openclaw-scanner

Helm chart for `openclaw-scanner` — the continuous compliance scanning
daemon that re-attests listings in the openclaw-skill-store on a
configurable interval.

## Compliance posture

FedRAMP High via the `fedramp-high` overlay (cascades
`fedramp-moderate`). See `lareira-openclaw-pki/README.md` for the full
mechanical surface.

This chart additionally emits:

- `sekiban.pleme.io/CompliancePolicy` + `SignatureGate`
- NetworkPolicy egress allowlist to the store + PKI services
- Multi-replica with PDB minAvailable 1 (read-only, idempotent)

## Operation

The scanner runs as a long-running Deployment. Each replica owns its
own interval timer; webhook output should be deduped downstream when
`replicaCount > 1`. The status API is on `:8081`.

## Endpoints

| Path | Purpose |
|---|---|
| `GET /health` | Liveness + readiness |
| `GET /api/v1/status` | Last-scan summary, drift counts |
| `GET /metrics` | Prometheus scrape |

## Usage

```bash
helm install openclaw-scanner oci://ghcr.io/pleme-io/charts/lareira-openclaw-scanner \
  --namespace openclaw \
  --set "pleme-microservice.image.tag=sha256:<digest>" \
  --set scanIntervalSecs=1800
```
