# openclaw stack — attachment gating

How tameshi-shaped admission applies to *anything that attaches to
openclaw* once the stack itself is running. The deploy-time gating
(see [RELEASE-FLOW.md](./RELEASE-FLOW.md)) gates the openclaw stack as
a whole; this document covers the runtime gates that govern who can
talk to it and how.

## Three classes of attachment

| Class | What | Gating |
|---|---|---|
| **Skill listings** | Publishers POST `CompliantListing<SkillKind>` JSON to the store | Tameshi merkle-proof verification at admission (in-store, today) |
| **Publisher enrollment** | Publishers POST to the PKI to issue a cert | Org-match + input validation (today); per-request signature verification (planned) |
| **Service-to-service** | scanner ↔ store ↔ pki | NetworkPolicy allowlists + sekiban-attested workload identity |

All three rest on the **same tameshi root of trust**: the org-seed
held in Borealis DFC and signed via the publisher PKI. A break of the
PKI org-seed compromises all three; the org-seed's threat model is
covered in [THREAT-MODEL.md](./THREAT-MODEL.md) §G2.

## 1. Skill listings (the openclaw value proposition)

This is the strongly-gated path today, owned by `openclaw-skill-store`:

```
publisher                                     openclaw-skill-store
   │                                                  │
   │  POST /api/v1/skills                             │
   │  body: CompliantListing<SkillKind> {             │
   │    publisher_id, public_key, ...                 │
   │    merkle_proofs: [...],                         │
   │    pillar_seal: { compliance_hash, ... },        │
   │    composed_root, signed_root: SignedRoot, ...   │
   │  }                                               │
   │ ───────────────────────────────────────────────► │
   │                                                  │
   │                                                  │  1. verify_invariants()
   │                                                  │     — recompute every hash
   │                                                  │     — check merkle paths
   │                                                  │     — check pillar_seal
   │                                                  │  2. verify signed_root against
   │                                                  │     publisher's cert (from PKI)
   │                                                  │  3. check publisher not in CRL
   │                                                  │     (latest /crl from PKI)
   │                                                  │  4. check NIST/EU-AI-Act/etc.
   │                                                  │     framework profile coverage
   │                                                  │
   │ ◄─────────────────────────────────────────────── │
   │  200 + listing_id   OR   4xx + structured error  │
```

**Defenses by attack:**

| Attacker action | What breaks | Defense |
|---|---|---|
| Forge merkle proof | Recomputed hash mismatches `composed_root` | Step 1 |
| Replace publisher_id with a different known one | The `cert` field's BLAKE3 doesn't match | Step 2 |
| Steal a publisher's cert and submit | If revoked, in CRL | Step 3 |
| Submit a listing missing required compliance frameworks | Profile coverage gap | Step 4 |
| Tamper with frontmatter post-pangea-publish-skill | Any of the four hashes breaks | Step 1 |

**Tested by:** `openclaw-skill-store` test suite (in that repo).

**Not tested in this stack today:** an end-to-end test that exercises
the full publish flow against a deployed stack. This is in scope for a
followup chart-of-charts integration test.

## 2. Publisher enrollment (PKI-side)

This is the path our PKI binary owns. **Honest current state:**

```
publisher                                     openclaw-publisher-pki
   │                                                  │
   │  POST /enroll                                    │
   │  body: { publisher_id, public_key, org }         │
   │ ───────────────────────────────────────────────► │
   │                                                  │
   │                                                  │  1. validate_publisher_id()
   │                                                  │     — ASCII alnum + .-_@+, max 256
   │                                                  │  2. validate_public_key()
   │                                                  │     — 16..4096 bytes
   │                                                  │  3. validate_org()
   │                                                  │     — match req.org == config.org
   │                                                  │
   │ ◄─────────────────────────────────────────────── │
   │  200 + signed cert                               │
```

**This is intentionally light**, with the production posture being:

- The PKI is `ClusterIP` only; not reachable from outside the cluster.
- It sits **behind Authentik OIDC at the gateway** (saguão fleet
  identity). The gateway authenticates the user and injects an
  `X-Authentik-User` header before the request reaches the PKI pod.
- The chart's `compliance.authn.oidc.provider: authentik` annotation is
  consumed by `pleme-admission-policies` to enforce that the OIDC
  forward-auth chain is in place — a misconfigured ingress fails admission.

**What's NOT enforced today (and why):**

| Threat | Current defense | Future defense |
|---|---|---|
| Internal pod impersonates a publisher | NetworkPolicy: only specific pods can dial the PKI | Per-request signed body — the publisher signs `(publisher_id || public_key || nonce || timestamp)` with their *fresh* keypair so the PKI verifies the requester actually controls the key being enrolled |
| Replay of a captured `/enroll` request | None today | Nonce + 5-minute timestamp window |
| Stale CRL — revoked publisher still served | Scanner cadence (default 1h), tunable down to 60s | Push notification from PKI to scanner on revoke |

**The signed-request defense is straightforward to add later** — it's a
~30 LOC change in `src/api.rs` (parse signature, verify against the
incoming public_key, reject on mismatch). Tracking as a Phase-2
hardening task; the design is captured here so the future PR has
clear acceptance criteria.

## 3. Service-to-service attachments

The three openclaw services talk to each other over `ClusterIP`. The
conversation is gated by:

| From | To | Gating |
|---|---|---|
| store → pki | NetworkPolicy: `app.kubernetes.io/name: openclaw-skill-store` may dial port 8090 | + sekiban admission ensures both pods carry valid composite signatures |
| scanner → store | NetworkPolicy: `app.kubernetes.io/name: openclaw-scanner` may dial port 8080 | + sekiban admission |
| scanner → pki | NetworkPolicy: scanner may dial port 8090 | + sekiban admission |

**Why this is sufficient for now:** all three services were admitted
to the cluster by sekiban after presenting valid composite signatures.
A pod that wasn't admitted by sekiban cannot exist in the namespace.
NetworkPolicy then narrows further: even if some other pod *were*
admitted (e.g. a debug shell), it can't dial the openclaw services
unless its labels match the allowlist.

**Why this could be tightened:** mTLS via Istio would add per-request
identity verification on the data plane (the pod's SPIFFE ID becomes
part of the request). The fedramp-high overlay's
`compliance.authn.istio.mtls.required: null` field defers to "auto at
fedramp-high" — when the cluster has Istio installed, mTLS is
automatically enforced. This is a cluster-side concern, documented in
[CLUSTER-PREREQUISITES.md](./CLUSTER-PREREQUISITES.md).

## Tested boundaries

The PKI repo's integration tests
(`openclaw-publisher-pki/tests/http_api.rs`) cover:

- ✓ enroll org-mismatch rejection
- ✓ enroll input validation (publisher_id format, public_key bounds, org slug)
- ✓ revoke: not-enrolled rejection, double-revoke rejection
- ✓ revoke: input validation (reason length, NUL bytes)
- ✓ CRL: empty initial state, sorted output, deterministic signature, signature changes on revoked-set growth
- ✓ Full lifecycle: enroll → org-root → revoke → CRL roundtrip

Not yet tested (in scope for cluster-bringup followup):

- ✗ End-to-end skill publish against the deployed store
- ✗ Cross-service NetworkPolicy enforcement (would need a cluster)
- ✗ sekiban admission rejection on signature mismatch (would need a cluster)
- ✗ CompliancePolicy re-run drift detection (would need a cluster)

The four uncovered boundaries are inherently cluster-dependent. The
smoke test (`openclaw-publisher-pki/examples/smoke.rs --e2e`) exercises
the first three against a live deployment as part of post-bringup
verification.

## Mapping to the threat model

The boundaries above correspond to attack categories in
[THREAT-MODEL.md](./THREAT-MODEL.md):

| Threat-model goal | Attachment-gating layer |
|---|---|
| G1 — Submit a non-compliant skill | Class 1 (skill listings) |
| G2 — Steal the org-seed | Pre-attachment (cluster floor) |
| G3 — DoS the store or PKI | Class 1 + Class 2 (input validation) + Class 3 (NetworkPolicy + HPA) |
| G4 — Tamper with stored listings | Class 1 (re-attestation by scanner) |
| G5 — Long-tail revocation gap | Class 2 (CRL) + Class 1 (scanner re-checks) |
