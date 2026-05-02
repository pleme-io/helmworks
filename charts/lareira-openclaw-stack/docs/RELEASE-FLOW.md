# openclaw stack — release flow

How a deployable openclaw release is produced from source.

## The chain

```
source repos (3 Rust services)
        │
        ▼  nix build .#dockerImage
multi-arch OCI images
        │
        ▼  cosign sign + SBOM + SLSA provenance
attested OCI images in ghcr.io/pleme-io/openclaw-*
        │
        ▼  helm package
chart bundles (lareira-openclaw-{pki,store,scanner,stack})
        │
        ▼  forge release-attest
release-values.yaml with:
  • image.repository@sha256:<digest>          (CM-2, SI-7)
  • attestation.signature                      (master tameshi sig)
  • attestation.certificationHash              (BLAKE3 over image+chart+rbac)
  • attestation.complianceHash                 (BLAKE3 over kensa results)
  • attestation.changesetHash                  (BLAKE3 over git changeset)
        │
        ▼  helm install / FluxCD HelmRelease
chart-time validators check attestation completeness
        │
        ▼  manifests reach the cluster
sekiban admission webhook verifies signature against the workload
        │
        ▼  pod admitted
periodic re-verification every signatureGate.verificationIntervalSecs
        │
        ▼
running, attested, FedRAMP-High openclaw stack
```

Each step is **mechanical** — same input → same output. A missing or
wrong substitution breaks a hash and the release fails to render.

## Per-step details

### 1. Build OCI images (`nix build .#dockerImage`)

```bash
# Per service repo:
cd openclaw-publisher-pki && nix build .#dockerImage
cd openclaw-skill-store    && nix build .#dockerImage
cd openclaw-scanner        && nix build .#dockerImage
```

`rust-service-flake.nix` produces a multi-arch OCI image with a
content-addressed digest. Push to `ghcr.io/pleme-io/<service>` and
capture the returned digest:

```bash
DIGEST=$(crane digest ghcr.io/pleme-io/openclaw-publisher-pki:latest)
echo "image digest: ${DIGEST}"
```

### 2. Attest the image

```bash
# Cosign keyless via OIDC (the canonical pleme-io path).
cosign sign --yes ghcr.io/pleme-io/openclaw-publisher-pki@${DIGEST}

# SBOM in SPDX format.
syft ghcr.io/pleme-io/openclaw-publisher-pki@${DIGEST} -o spdx-json > sbom.json
cosign attest --yes --predicate sbom.json --type spdx \
  ghcr.io/pleme-io/openclaw-publisher-pki@${DIGEST}

# SLSA build provenance (forge emits this directly).
cosign attest --yes --predicate slsa-provenance.json --type slsaprovenance \
  ghcr.io/pleme-io/openclaw-publisher-pki@${DIGEST}
```

### 3. Run kensa against the rendered chart

```bash
# Render the chart with the (now-known) digest, in dry-run mode.
helm template release helmworks/charts/lareira-openclaw-pki \
  --set "pleme-microservice.image.tag=${DIGEST}" \
  --set "pleme-microservice.attestation.signature=PLACEHOLDER" \
  --set "pleme-microservice.attestation.certificationHash=PLACEHOLDER" \
  --set "pleme-microservice.attestation.complianceHash=PLACEHOLDER" \
  > rendered.yaml

# Run kensa with NIST 800-53 high profile.
kensa run --profile nist-800-53-high --manifest rendered.yaml \
  --output kensa-attestation.json
```

`kensa-attestation.json` contains a `ComplianceResult` with per-control
status. The `complianceHash` field of the chart's attestation block is
BLAKE3 of this file's canonical bytes.

### 4. Compute the four attestation hashes

```bash
# tameshi composes a master signature over four pillars:
#   1. master_signature  — Ed25519 sig over (certificationHash || complianceHash || changesetHash)
#   2. certificationHash — BLAKE3 over image_digest || chart_render
#   3. complianceHash    — BLAKE3 over kensa-attestation.json bytes
#   4. changesetHash     — BLAKE3 over git diff between this and previous release tag
tameshi attest \
  --image ghcr.io/pleme-io/openclaw-publisher-pki@${DIGEST} \
  --chart-render rendered.yaml \
  --kensa-result kensa-attestation.json \
  --git-changeset HEAD~1..HEAD \
  --signer akeyless-dfc:openclaw-release \
  --output release-attestation.json
```

The output is consumed in step 5.

### 5. Stamp the release values

```bash
# forge release-attest reads release-attestation.json and emits the
# operator-deployable values overlay.
forge release-attest \
  --chart lareira-openclaw-pki \
  --image ghcr.io/pleme-io/openclaw-publisher-pki@${DIGEST} \
  --attestation release-attestation.json \
  --output release-values.openclaw-pki.yaml
```

The output looks like:

```yaml
# release-values.openclaw-pki.yaml — STAMPED by forge at release time.
# Re-deriving requires the same source tree + tameshi key; tampering
# is detected by the chart's attestation gate at template render.
pleme-microservice:
  image:
    repository: ghcr.io/pleme-io/openclaw-publisher-pki@sha256:<DIGEST>
    tag: ""
  attestation:
    enabled: true
    signature: blake3:<MASTER_SIG>
    certificationHash: blake3:<CERT>
    complianceHash: blake3:<COMP>
    changesetHash: blake3:<CHANGESET>
  compliance:
    overlays: [fedramp-high, supplychain]
    enforce: true
sekiban:
  enabled: true
```

### 6. Operator deploy

```bash
helm install openclaw oci://ghcr.io/pleme-io/charts/lareira-openclaw-stack \
  --namespace openclaw \
  --create-namespace \
  -f release-values.openclaw-pki.yaml \
  -f release-values.openclaw-store.yaml \
  -f release-values.openclaw-scanner.yaml
```

If forge didn't stamp all three release-values files, the missing one's
attestation gate fires `fail()` at template render and the install
aborts.

### 7. Cluster admits the workload

sekiban's ValidatingAdmissionWebhook is configured to:
1. Look up the `SignatureGate` named after the workload
2. Compute the actual signature of (image digest + chart render +
   resolved RBAC) on the incoming Deployment / Service
3. Compare to `expectedSignature` (which equals
   `attestation.signature` per the chart's single-source wiring)
4. Reject CREATE/UPDATE on mismatch

### 8. Continuous re-verification

Every `signatureGate.verificationIntervalSecs` (default 3600s):
- sekiban re-runs steps 7.2 + 7.3 against the running workload
- If the live state diverges from the signature (e.g. a Deployment
  spec mutation that wasn't in the signed manifest), the SignatureGate
  is marked `Stale` and an alert fires
- The CompliancePolicy is also re-run on its `schedule` (default every
  6 hours) to detect compliance drift independent of signature drift

## What the chain proves

Given:
- The cluster admin trusts the akeyless-dfc key (org-level)
- The forge release pipeline is itself attested (tameshi self-attestation)
- The kensa runner image is digest-pinned + sekiban-gated

Then a successful deploy proves:
- The image bytes match a known digest (CM-2, SI-7)
- The image was signed by the org (CM-7, SI-3)
- The image has an SBOM (supply-chain transparency)
- The image was built with SLSA provenance (CM-3)
- The chart render satisfied NIST 800-53 high (kensa attestation)
- The chart values weren't tampered between forge and helm
  (chart attestation gate)
- The Kubernetes admission accepted the workload only after
  re-verifying the composite signature (sekiban)

A break anywhere — image swap, chart-values tampering, kensa
regression, sig mismatch — surfaces as a hard rejection at the earliest
possible boundary.

## Bootstrap (cluster has nothing yet)

For the first release of a NEW cluster:

1. Cluster admin installs `cert-manager`, `kyverno`, `external-secrets`
   manually
2. Apply `pleme-admission-policies` Helm release with
   `compliance.overlays={fedramp-high,supplychain}`
3. Apply `sekiban` Helm release (the chart is itself sekiban-gated, so
   bootstrap relies on `sekiban.crds.install: true` + a one-time admin
   apply)
4. Provision the openclaw org-seed via `cofre apply`
5. Apply the openclaw stack `HelmRelease`

After step 5, every subsequent release goes through the full chain.
The bootstrap window is the only "trust the operator" moment in the
lifecycle; everything afterward is mechanical.

## See also

- [`ARCHITECTURE.md`](./ARCHITECTURE.md) — runtime mental model
- [`THREAT-MODEL.md`](./THREAT-MODEL.md) — what this gating defeats
- [`CLUSTER-PREREQUISITES.md`](./CLUSTER-PREREQUISITES.md) — what must
  be true before step 6
- [`pleme-io/forge`](https://github.com/pleme-io/forge) — the
  release-attest implementation
- [`pleme-io/tameshi`](https://github.com/pleme-io/tameshi) — the
  signing primitives + Akeyless DFC integration
