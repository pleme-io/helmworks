# lareira-openclaw-pki

Helm chart for `openclaw-publisher-pki` — the publisher enrollment +
signed CRL HTTP server for the openclaw skill-store ecosystem.

## Compliance posture

FedRAMP High, mechanically. The chart depends on `pleme-microservice`
and declares `compliance.overlays: [fedramp-high]`, which cascades
`fedramp-moderate` and emits:

- chart-time `fail()` validators rejecting non-compliant input
- `runAsNonRoot=true`, `readOnlyRootFilesystem=true`, drop ALL caps,
  `seccompProfile=RuntimeDefault`, `automountServiceAccountToken=false`
- digest-pinned image (`@sha256:...`) — required, not optional
- default-deny + allow-DNS + allow-TLS-egress NetworkPolicies, plus
  this chart's allowlist for `openclaw-skill-store` and
  `openclaw-scanner` ingress
- `replicaCount >= 2`, `PodDisruptionBudget` with `minAvailable: 2`,
  topology spread over zone + hostname (CP-2)
- mandatory `ServiceMonitor` for `/metrics` (AU-2, AU-12, SI-4)
- `compliance-manifest` ConfigMap describing covered controls
- compliance.pleme.io/* labels and annotations on every resource
- Kyverno ClusterPolicies emitted by `pleme-admission-policies` enforce
  the same controls at admission — symmetric proof

In addition, this chart emits:

- `sekiban.pleme.io/CompliancePolicy` binding the workload to
  NIST 800-53 high via the kensa runner
- `sekiban.pleme.io/SignatureGate` requiring a valid composite tameshi
  signature for the deployment
- `external-secrets.io/ExternalSecret` materializing the PKI
  org-seed (CA root key) from a backend secret store — never embedded
  in chart values

## Usage

```bash
# 1. Provision the org-seed secret in your backend (cofre).
cofre apply --manifest manifests/openclaw-pki-org-seed.yaml

# 2. Install the chart.
helm install openclaw-pki oci://ghcr.io/pleme-io/charts/lareira-openclaw-pki \
  --namespace openclaw \
  --create-namespace \
  --set org=pleme-io \
  --set "pleme-microservice.image.tag=sha256:<digest>"
```

CI substitutes the real image digest and tameshi signature at release
time. A placeholder digest of all zeros causes the fedramp-high
overlay to `fail()` at template render — chart authors cannot
accidentally ship an unpinned image.

## Endpoints

| Path | Purpose |
|---|---|
| `POST /enroll` | Enroll a new publisher; returns signed cert |
| `GET /org-root` | Public org root hash (downstream pin target) |
| `POST /revoke` | Revoke a publisher |
| `GET /crl` | Get signed CRL |

## Notes

The `openclaw-publisher-pki` source repo is hosted at
`pleme-io/openclaw-publisher-pki`. This chart consumes the OCI image
published by that repo's CI; chart updates are tracked independently.
