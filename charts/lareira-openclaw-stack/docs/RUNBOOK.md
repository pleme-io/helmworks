# openclaw stack — operator runbook

Common tasks an on-call operator performs against a deployed stack.

## Health checks

```bash
# Quick: is everything running?
kubectl -n openclaw get \
  deploy,svc,signaturegate,compliancepolicy,externalsecret \
  -l pleme.io/part-of=openclaw

# Detailed: check sekiban verification status.
kubectl -n openclaw get signaturegate -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.lastVerifiedAt}{"\n"}{end}'

# Detailed: check kensa compliance status.
kubectl -n openclaw get compliancepolicy -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.controlsSatisfied}/{.status.controlsAssessed}{"\n"}{end}'
```

A healthy stack shows `Verified` for every SignatureGate and `Compliant`
for every CompliancePolicy with `controlsSatisfied == controlsAssessed`.

## Smoke test (after install or upgrade)

```bash
# Port-forward to the store; PKI is internal-only.
kubectl -n openclaw port-forward svc/openclaw-store-openclaw-skill-store 8080:8080 &

# 1. Health.
curl -fsS http://localhost:8080/health
# 2. List skills (should be 200 with empty array on a fresh deploy).
curl -fsS http://localhost:8080/api/v1/skills | jq .
# 3. Metrics.
curl -fsS http://localhost:8080/metrics | grep openclaw_

kill %1
```

A scripted version is at
[`scripts/smoke.sh`](../scripts/smoke.sh) (relative to the chart).

## Provision the org-seed

The PKI signs everything with a 32-byte seed treated as CA root key
material. The seed is materialized at runtime via ExternalSecret; the
operator provisions it once via `cofre`.

```bash
# Generate a 32-byte seed locally — never commit this.
SEED=$(openssl rand -hex 32)

# Apply via cofre.
cat <<EOF > /tmp/org-seed-manifest.yaml
- backend: sops
  path: openclaw/publisher-pki/org-seed
  property: hex
  value: ${SEED}
EOF
cofre apply --manifest /tmp/org-seed-manifest.yaml
shred -uvz /tmp/org-seed-manifest.yaml

# Verify the External Secret materializes.
kubectl -n openclaw get externalsecret openclaw-pki-org-seed -o yaml | grep -i 'syncedRevision\|conditions'
```

For production: rotate to a Borealis DFC key (key never in one piece)
and swap `LocalSigner` → `BorealisDfcSigner` in the PKI source. See
`openclaw-publisher-pki/src/signing.rs`.

## Enroll a new publisher

```bash
kubectl -n openclaw port-forward svc/openclaw-pki-openclaw-publisher-pki 8090:8090 &

curl -fsS -XPOST http://localhost:8090/enroll \
  -H 'content-type: application/json' \
  -d "$(jq -n --arg id "alice@pleme.io" \
              --arg org "pleme-io" \
              --argjson key "$(openssl rand -hex 32 | xxd -r -p | jq -Rs '. | tostring | [.[]] | map(. * 1)')" \
              '{publisher_id: $id, public_key: $key, org: $org}')" \
  | jq .

kill %1
```

`alice@pleme.io` is now enrolled; her cert + org context are returned in
the response. Cache the cert locally — it's needed when she signs a
listing.

## Revoke a publisher

```bash
kubectl -n openclaw port-forward svc/openclaw-pki-openclaw-publisher-pki 8090:8090 &

curl -fsS -XPOST http://localhost:8090/revoke \
  -H 'content-type: application/json' \
  -d '{"publisher_id":"alice@pleme.io","reason":"key compromised 2026-05-02"}' \
  | jq .

# Confirm she's in the CRL.
curl -fsS http://localhost:8090/crl | jq '.revoked[] | select(.publisher_id == "alice@pleme.io")'

kill %1
```

The scanner picks this up on its next cycle (default 1h). For a hot
incident, accelerate the cycle:

```bash
# Reduce scan interval to 60s temporarily.
helm upgrade openclaw oci://ghcr.io/pleme-io/charts/lareira-openclaw-stack \
  --reuse-values \
  --set "scanner.scanIntervalSecs=60"
```

## Investigate a failed re-attestation

The scanner emits an alert via the configured webhook + ServiceMonitor
metrics when a previously-admitted listing fails to re-verify.

```bash
# 1. Find the failing listing.
kubectl -n openclaw logs deploy/openclaw-scanner-openclaw-scanner --since=1h | \
  grep -E 'attestation_failed|drift_detected'

# 2. Re-fetch the listing manually.
LISTING_ID="alice@pleme.io/my-skill@1.0.0"
curl -fsS http://localhost:8080/api/v1/skills/${LISTING_ID}/verify | jq .

# 3. Check if the publisher is in the CRL.
curl -fsS http://localhost:8090/crl | jq --arg p "${LISTING_ID%/*}" '.revoked[] | select(.publisher_id == $p)'
```

If the publisher is in the CRL, the listing is expected to fail — the
revocation is doing its job. Mark the listing as superseded.

If the publisher is NOT in the CRL, the listing has been tampered with.
Treat as a security incident: capture the failing listing JSON, roll
back to the last known-good version of the postgres database, audit log
access between the previous good scan and now.

## Rotate the org-seed

**Last resort.** Org-seed rotation invalidates every existing publisher
cert. Coordinate with all publishers before rotation.

```bash
# 1. Communicate the rotation window to publishers (they must re-enroll).
# 2. Generate a new seed in cofre under a versioned key.
SEED_V2=$(openssl rand -hex 32)
cat <<EOF > /tmp/seed-v2.yaml
- backend: sops
  path: openclaw/publisher-pki/org-seed-v2
  property: hex
  value: ${SEED_V2}
EOF
cofre apply --manifest /tmp/seed-v2.yaml
shred -uvz /tmp/seed-v2.yaml

# 3. Update the chart's externalSecret remoteRef.key to "openclaw/publisher-pki/org-seed-v2".
helm upgrade openclaw … --set "pki.orgSeed.externalSecret.remoteRef.key=openclaw/publisher-pki/org-seed-v2"

# 4. Force pod restart so new env is mounted.
kubectl -n openclaw rollout restart deploy/openclaw-pki-openclaw-publisher-pki

# 5. Wait until /org-root returns the new public-key-hash.
# 6. All publishers re-enroll within the rotation window.
# 7. Old listings re-attest under the new org-root after publishers re-sign.
```

In production the rotation is automated by a tameshi-attested job; the
above is the manual fallback.

## Scale up under load

```bash
# Increase store HPA ceiling (default 10).
helm upgrade openclaw … --set "store.pleme-microservice.autoscaling.maxReplicas=20"

# Add scanner replicas (default 2; replicas dedupe via webhook idempotency).
helm upgrade openclaw … --set "scanner.pleme-microservice.replicaCount=4"
```

## Disaster — entire namespace lost

The stack is fully reconcilable from the FluxCD `HelmRelease` + the
cofre-managed org-seed. Recovery:

```bash
# 1. Recreate the namespace.
kubectl create namespace openclaw

# 2. Trigger the FluxCD reconciliation.
flux reconcile helmrelease openclaw -n flux-system --with-source

# 3. The ExternalSecret will materialize the org-seed from Borealis.
# 4. The postgres replica reconnects (state preserved if CNPG was on a
#    separate PVC).
# 5. Listings are re-verified by the scanner on its next cycle.
```

If the postgres data was lost too: every publisher re-submits their
listings via `pangea-publish-skill`. The merkle proofs are
deterministic; same input produces the same listing JSON.
