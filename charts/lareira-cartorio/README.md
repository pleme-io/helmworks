# lareira-cartorio

The **central merkle ledger** for the openclaw ecosystem. Admits OCI
images, helm charts, and skills only with valid tameshi attestation
chains.

## v0.3.0 — durable storage (cartorio v0.5.0+)

Backends:

- **memory** (default) — ephemeral; loses state on Pod restart. Matches
  v0.2.x chart behavior.
- **postgres** — multi-replica durable. See `examples/values-postgres.yaml`
  for the canonical CNPG / akeyless External Secrets wiring.
- **sqlite** — single-replica durable; pending pleme-microservice
  `extraVolumes` hook (helmworks v0.7). Today's sqlite-backed deploys
  use a hand-rolled Deployment outside this chart.

Quick switch to Postgres:

```bash
helm upgrade --install cartorio . \
  --values examples/values-postgres.yaml \
  --set persistence.postgres.existingSecret=cartorio-postgres
```

Audit-consistency loop cadence is configurable via
`auditIntervalSecs` (default 900s). Set to 0 to disable.

This is the load-bearing piece every other gate references:

- **Zot pre-push webhook** asks: "is this digest in the ledger?"
- **Kyverno `verifyImages` policy** asks: "verify before admitting Pod"
- **`openclaw-scanner` re-attestation** asks: "is the proof still valid?"

Tampering anywhere breaks a hash and the artifact is rejected.

## Compliance posture

FedRAMP High via the `fedramp-high` overlay (cascades `fedramp-moderate`).
See `lareira-openclaw-pki/README.md` for the full mechanical surface.
This chart additionally emits:

- `sekiban.pleme.io/CompliancePolicy` + `SignatureGate` (the registry's
  own deployment is gated by tameshi — the gate cannot ship without
  itself satisfying the gate)
- NetworkPolicy allowlists for Zot, scanner, Kyverno
- PDB minAvailable 2

## Endpoints

| Path | Purpose |
|---|---|
| `POST /api/v1/artifacts` | Admit a `CompliantArtifact` (verifies merkle + signature shape; rejects on tampering) |
| `GET  /api/v1/artifacts` | List (paged; `?kind=oci-image\|helm-chart\|skill` filter) |
| `GET  /api/v1/artifacts/{id}` | Fetch one |
| `GET  /api/v1/artifacts/{id}/verify` | Re-verify a record |
| `GET  /api/v1/artifacts/by-digest/{digest}` | Lookup by content digest |
| `GET  /api/v1/merkle/root` | Composed deterministic root over all admitted leaves |
| `GET  /health` | Liveness + readiness |
| `GET  /metrics` | Prometheus scrape |

## What admission verifies

```
POST /api/v1/artifacts
       │
       ├─ shape validation: name, version, publisher_id, org, digest
       ├─ org match (req.org == config.org)
       ├─ recompose merkle root from declared fields
       │     ↳ must equal signed_root.root
       ├─ pillar coverage: required pillars per kind must be present
       │     ↳ oci-image: source + build + image + compliance
       │     ↳ helm-chart: source + build + compliance
       │     ↳ skill:     source + compliance
       ├─ compliance.status must be Compliant
       ├─ no duplicate digest already in ledger
       │
       └─ admit (otherwise 4xx with structured error)
```

## Polymorphism — one ledger, many leaf shapes

Each admitted artifact is one leaf. The ledger holds them all together
and the deterministic ledger root composes over every leaf's
`composed_root`. The leaf shape varies by kind (each kind requires
different attestation pillars), but they live in the same merkle tree
and verify the same way.

## Usage

```bash
helm install openclaw-registry oci://ghcr.io/pleme-io/charts/lareira-cartorio \
  --namespace openclaw \
  --set "pleme-microservice.image.tag=sha256:<digest>" \
  --set "pleme-microservice.attestation.signature=blake3:..." \
  --set "pleme-microservice.attestation.certificationHash=blake3:..." \
  --set "pleme-microservice.attestation.complianceHash=blake3:..."
```

CI substitutes the real values; placeholder zeros fail() at template render.

## See also

- [`lareira-openclaw-stack/docs/ARCHITECTURE.md`](../lareira-openclaw-stack/docs/ARCHITECTURE.md) — the full openclaw stack architecture
- [`lareira-openclaw-stack/docs/RELEASE-FLOW.md`](../lareira-openclaw-stack/docs/RELEASE-FLOW.md) — how artifacts get admitted (the source side of this registry)
- `pleme-io/cartorio` — the source repo
