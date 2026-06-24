# openclaw stack — architecture

## Frame

The openclaw stack is a tameshi-attested skill-store ecosystem. Every
listing the store admits carries a merkle proof anchored to a per-org
root signed by the publisher PKI. Publishers may be revoked at any time;
the scanner re-attests every admitted listing on a configurable cadence
and emits drift alerts when a proof no longer verifies or a publisher's
cert lands in the CRL.

The deployment posture is **FedRAMP High** by construction —
`compliance.overlays: [fedramp-high]` in each sub-chart's
`pleme-microservice` values cascades through the pleme-lib overlay
registry, emitting chart-time validators + cluster-side Kyverno
policies for 30 NIST 800-53 controls (see `compliance.pleme.io/controls`
annotation on every emitted resource).

## Components

```
                    ┌──────────────────────────────────────┐
                    │          PUBLISHER (CLIENT)           │
                    │   pangea-publish-skill orchestrator   │
                    │   builds CompliantListing<SkillKind>  │
                    └─────────────────┬────────────────────┘
                                      │
                                      │ 1. enroll → cert
                                      ▼
                    ┌──────────────────────────────────────┐
                    │       lareira-openclaw-pki          │
                    │   /enroll  /org-root  /revoke  /crl │
                    │   org-seed via ExternalSecret        │
                    │   ClusterIP :8090 (internal-only)    │
                    └─────┬─────────────────────────┬─────┘
                          │                          │
              org-root pin│                  CRL diff │
                          ▼                          │
                    ┌──────────────────────────────────────┐
                    │      lareira-openclaw-store         │
                    │   POST /api/v1/skills (admission)   │
                    │   GET  /api/v1/skills (browse)      │
                    │   GET  /api/v1/skills/{id}/verify   │
                    │   merkle ledger → Postgres (HA)     │
                    │   ClusterIP :8080 (gateway-fronted) │
                    └─────────────────┬───────────────────┘
                                      │
                       continuous re-attestation cadence
                                      │
                                      ▼
                    ┌──────────────────────────────────────┐
                    │     lareira-openclaw-scanner        │
                    │   Long-running daemon                │
                    │   Re-fetches every listing on a     │
                    │   schedule, re-verifies merkle      │
                    │   proofs against current org-root + │
                    │   CRL, emits drift alerts            │
                    │   ClusterIP :8081 (status API)       │
                    └──────────────────────────────────────┘

       ▲ All three workloads sit behind the sekiban admission webhook
       │ which checks tameshi composite signatures + a NIST 800-53 high
       │ compliance policy at every CREATE/UPDATE.
```

## Trust boundaries

```
┌─────────────────────────────────────────────────────────────────────┐
│ CLUSTER FLOOR (pangea-architectures: fedramp_high.rb)              │
│ FlowLogsAll · CloudTrail · KMS · GuardDuty · SecurityHub ·         │
│ Config · WAF · encrypted log groups · LockedDefaultSg · etc.        │
├─────────────────────────────────────────────────────────────────────┤
│ ADMISSION (pleme-admission-policies + sekiban + kyverno)           │
│ Kyverno: digest-pinned images · no privileged · drop-ALL ·         │
│   readOnlyRootFilesystem · no host namespaces · no :latest          │
│ sekiban: SignatureGate verifies tameshi composite sig before       │
│   allowing CREATE/UPDATE on Deployment + Service                    │
├─────────────────────────────────────────────────────────────────────┤
│ NAMESPACE (lareira-openclaw-stack)                                 │
│ NetworkPolicy default-deny + DNS-allow + TLS-egress-allow          │
│ Custom service-to-service allowlists (store→pki, scanner→store+pki)│
│ External-Secrets-Operator materializes org-seed from cofre backend │
├─────────────────────────────────────────────────────────────────────┤
│ POD                                                                 │
│ runAsNonRoot · readOnlyRootFilesystem · capabilities.drop=ALL      │
│ seccompProfile=RuntimeDefault · automountServiceAccountToken=false │
│ replicaCount >= 2 (CP-2) · PDB minAvailable=2                      │
└─────────────────────────────────────────────────────────────────────┘
```

A request must traverse every layer to reach a workload pod. Each layer
is enforced independently — a regression in one is contained by the
next.

## Failure domains

| Component | Failure mode | Containment |
|---|---|---|
| pki | org-seed corrupted | sekiban admission rejects new pods (signature mismatch); existing publisher certs remain verifiable; CRL still served |
| pki | all replicas down | enroll/revoke/CRL unavailable; existing listings still verify against cached org-root pin until next scan |
| store | postgres unavailable | reads degraded; admissions rejected (writes fail); existing listings cached at the gateway remain |
| store | merkle ledger corrupted | CompliancePolicy detects drift; sekiban marks workload `Degraded`; alert fires |
| scanner | all replicas down | drift detection latency grows; existing listings keep their last-known good status |
| scanner | webhook sink unreachable | drift detection still runs; metrics + audit log still updated |

## Sources of authority

| Concern | Source of truth |
|---|---|
| PKI org-seed | cofre-managed Borealis DFC entry → ExternalSecret → projected env |
| Image digests | forge CI substitutes at release time; chart fail()s on placeholders |
| Compliance baseline | `compliance.overlays: [fedramp-high]` in pleme-lib overlay registry |
| NIST 800-53 mapping | `kensa/src/mapping/nist_800_53.rs` (built into kensa runner image) |
| Tameshi composite signature | injected by forge into sekiban CRDs at release time |
| Cluster compliance posture | `pangea-architectures/.../fedramp_high.rb` |

## See also

- [`THREAT-MODEL.md`](./THREAT-MODEL.md) — what an attacker can and can't do
- [`RUNBOOK.md`](./RUNBOOK.md) — operator playbooks for common tasks
- [`CLUSTER-PREREQUISITES.md`](./CLUSTER-PREREQUISITES.md) — what must be true on the target cluster
- [`pleme-io/theory/THEORY.md`](https://github.com/pleme-io/theory/blob/main/THEORY.md) — the wider frame
