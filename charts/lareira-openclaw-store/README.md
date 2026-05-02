# lareira-openclaw-store

Helm chart for `openclaw-skill-store` — the attested skill registry +
marketplace API for OpenClaw agents.

## Compliance posture

FedRAMP High via the `fedramp-high` overlay (cascades
`fedramp-moderate`). See `lareira-openclaw-pki/README.md` for the full
mechanical surface.

This chart additionally emits:

- `sekiban.pleme.io/CompliancePolicy` + `SignatureGate`
- A PVC bound to an `encrypted-default` storage class (SC-28)
- NetworkPolicy egress allowlist to the publisher PKI service
- HPA scaling 3 → 10 on CPU, with PDB minAvailable 2

## Endpoints

| Path | Purpose |
|---|---|
| `GET /health` | Liveness + readiness |
| `GET /api/v1/skills` | List admitted listings |
| `POST /api/v1/skills` | Submit a `CompliantListing<SkillKind>` JSON |
| `GET /api/v1/skills/{id}/verify` | Re-verify a listing's merkle proofs |
| `GET /metrics` | Prometheus scrape |

## Persistence

The merkle ledger is durable.

- `persistence.backend=sqlite` (default): PVC-backed; `Recreate`-style
  deploy. Suitable for HA via leader-elected single writer; current
  defaults run multi-replica reading from a shared PVC — switch to
  postgres for production.
- `persistence.backend=postgres`: external Postgres (e.g. CloudNativePG).
  Required for true HA.

## Usage

```bash
helm install openclaw-store oci://ghcr.io/pleme-io/charts/lareira-openclaw-store \
  --namespace openclaw \
  --set "pleme-microservice.image.tag=sha256:<digest>" \
  --set persistence.backend=postgres \
  --set persistence.postgres.host=cnpg-openclaw-rw.openclaw.svc
```
