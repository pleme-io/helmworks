# openclaw stack — threat model

## Trust assumptions

| Trusted | Untrusted |
|---|---|
| Cluster operator (cluster-admin) | All publishers |
| The Akeyless DFC backend (cluster's secret store) | All consumers of the public API |
| The forge CI pipeline (release attestation) | Network paths between cluster and external clients |
| The kensa + tameshi codebases | Image registries (we pin digests) |
| The pleme-lib overlay registry | Anyone who can reach cluster-edge ingress |

## Adversary model

We assume an attacker may:
- Submit arbitrary `CompliantListing<SkillKind>` payloads to the store
- Be a previously-enrolled publisher whose key was compromised
- Compromise a single store replica
- Compromise the scanner replica
- Reach the cluster from outside via the gateway
- See all DNS lookups in the cluster (worst-case observability)

We assume an attacker **cannot**:
- Run code on the same node as the PKI (that's a cluster-floor breach,
  out of scope for this stack)
- Sign anything with the org-seed unless they breach Akeyless DFC
- Modify the kensa runner image (digest-pinned, sekiban-gated)
- Bypass the sekiban admission webhook (it's a cluster-floor concern)

## Attacker goals × controls

### G1 — Submit a non-compliant skill to the store

| Step | Defense |
|---|---|
| Forge a listing JSON | Listing must include valid merkle proofs; tampering breaks a hash |
| Sign with stolen publisher cert | sekiban + CRL: revoked publishers' certs are rejected at re-attestation; pre-CRL window mitigated by short scanner cadence (default 1h, configurable down to 60s minimum) |
| Bypass admission via raw Pod create | Kyverno ClusterPolicy from `fedramp-high` overlay rejects: non-digest-pinned images, runAsRoot, host namespaces, missing security context |
| Spoof org membership | enroll requires `req.org == config.org` match; org-mismatch returns 400 |

### G2 — Steal the org-seed

| Step | Defense |
|---|---|
| Read it from a chart values file | Org-seed never appears in values; only `targetSecretName` does |
| Read it from the K8s Secret | RBAC on the namespace; ExternalSecret materializes; pod mounts via env from `secretKeyRef` |
| Read it from cluster-edge ingress | PKI is `ClusterIP`-only; not exposed externally |
| Read it from another pod | NetworkPolicy: only `app.kubernetes.io/name: openclaw-skill-store` and `app.kubernetes.io/name: openclaw-scanner` may dial port 8090 |
| Read it from the env of the running PKI process | Container has `readOnlyRootFilesystem`, drops ALL caps, runs as non-root; in-process exfil requires kernel exploit (cluster-floor concern) |
| Read it from Akeyless | DFC: key never exists in one piece; threshold reconstruction requires multiple shares |

The current implementation uses `LocalSigner` (single-piece seed in env);
**production deployments swap to `AkeylessDfcSigner` for threshold
signing**. This is documented in `openclaw-publisher-pki/src/signing.rs`
as the load-bearing one-line change.

### G3 — DoS the store or PKI

| Step | Defense |
|---|---|
| Flood `/enroll` with bogus payloads | Input validation rejects malformed: empty IDs, oversized public keys (max 4 KiB), forbidden chars; future: rate-limit middleware; HPA scales store 3 → 10 |
| Flood `/api/v1/skills` reads | HPA scales store; ServiceMonitor surfaces the burst; future rate-limit at gateway |
| Flood `/crl` with reads | CRL is signed once per state mutation; future cache layer |

### G4 — Tamper with stored listings

| Step | Defense |
|---|---|
| Modify a listing in postgres | Listing's merkle proof breaks; scanner re-attestation fails; sekiban marks workload `Degraded`; alert fires |
| Replace the postgres replica | The store reconnects with same credentials (sealed via SOPS); listings are content-addressed (BLAKE3) so a swap is detectable |
| Replay a valid listing under a different publisher_id | Cert binds publisher_id || public_key || org via BLAKE3; replay attempt produces a different cert root |

### G5 — Long-tail revocation gap

If a publisher's key is compromised, the window between compromise and
detection is bounded by the scanner cadence (`SCAN_INTERVAL_SECS`,
default 3600s, validated 60s ≤ x ≤ 86400s). Operators can shorten this
on a hot incident.

The CRL itself is signed; a compromised PKI cannot quietly remove a
revocation entry — the CRL root would change, scanner detects.

## Out of scope

| Concern | Where it lives |
|---|---|
| Kernel CVE in container runtime | cluster-floor (pangea-architectures) |
| Compromise of the Akeyless backend | Akeyless org's threat model |
| Compromise of forge CI | forge's signed-build invariants + tameshi ledger |
| Compromise of the kensa container image | digest-pinned at admission; image attested via separate tameshi chain |
| Side-channel timing attacks on the BLAKE3 keyed-HMAC signer | accepted for `LocalSigner`; not present in `AkeylessDfcSigner` (operator-grade prod) |

## Audit hooks

Every action emits structured logs at `info` level:
- `enroll`: publisher_id, org, issued_at
- `revoke`: publisher_id, reason, revoked_at
- `crl`: publisher_count, revoked_count, root_hash, signed_at
- `org_root`: signed_at

These flow through the cluster log pipeline (Vector → VictoriaLogs on
homelab; Vector → Splunk HEC on SaaS). Retention is 365 days per
`compliance.audit.retentionDays: 365` in chart values (AU-11).

The tameshi composite signature on the deployment itself is verified by
sekiban before any pod is admitted, providing the chain back to the
forge release that produced it.
