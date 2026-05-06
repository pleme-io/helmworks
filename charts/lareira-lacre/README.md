# lareira-lacre

The **OCI gate** for the openclaw ecosystem. Reverse proxy that gates
`PUT /v2/{name}/manifests/{ref}` through cartorio. Sits in front of any
backing OCI registry — Zot (default in `lareira-openclaw-stack`), ECR,
GHCR mirror, or any other OCI Distribution Spec implementation.

The gate is **content-addressed**: lacre hashes the actual manifest body
and asks cartorio about that digest, never trusting the URL reference.
Tag-spoofing attacks where a client claims a known-good digest in the
URL but supplies different bytes are rejected because the body's hash
doesn't match the URL's reference.

```
docker push registry.example.com/myorg/myimage:v1
   ↓ (Ingress)
lacre PUT /v2/myorg/myimage/manifests/v1
   ↓ sha256(manifest body) = sha256:abc…
   ↓ GET cartorio/api/v1/artifacts/by-digest/sha256:abc…
   ↓
   ↓ 200 + status=Active + org match  →  forward to backend
   ↓ 404                              →  403 "no compliant listing"
   ↓ status=Revoked|Quarantined|…     →  403 "<reason>"
   ↓ wrong org                        →  403 "registered under X"
```

## Compliance posture

FedRAMP High via the `fedramp-high` overlay (cascades `fedramp-moderate`).
This chart additionally emits:

- `sekiban.pleme.io/CompliancePolicy` + `SignatureGate` (lacre's own
  deployment is gated by tameshi — the gate cannot ship without itself
  satisfying the gate)
- NetworkPolicy: ingress allowed from the `ingress-nginx` namespace,
  egress allowed to cartorio (port 8082) + the backing registry
  (port 5000)
- PDB minAvailable 2

## Endpoints

| Path | Purpose |
|---|---|
| `PUT /v2/{name}/manifests/{ref}` | gated push — body-hashed and asked of cartorio |
| `GET /v2/{name}/manifests/{ref}` | passthrough to backend |
| `GET /v2/{name}/blobs/{digest}` | passthrough to backend |
| `GET /health` | liveness + readiness |
| `GET /metrics` | prometheus scrape |

## Wiring inside the umbrella stack

When deployed via `lareira-openclaw-stack`, the umbrella's NOTES.txt
documents the canonical defaults; this chart's `cartorio.serviceHost`,
`backend.url`, and `org` values are pre-wired to the stack's other
sub-chart names so a single `helm install lareira-openclaw-stack` boots
a complete proof chain.
