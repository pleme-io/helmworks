# Air-Gap K8s Compliance Research Brief

**For:** `pleme-io/helmworks` `pleme-lib` compliance primitive expansion
**Frame:** maps onto existing `_compliance_*.tpl` surface; each section ends with primitives to add.
**Date:** 2026-04-27. All citations are best-known authoritative versions as of cutoff.

---

## 1. NSA / CISA Kubernetes Hardening Guidance

**Doc:** *Kubernetes Hardening Guide*, NSA & CISA, **Cybersecurity Technical Report (CTR)**, **Version 1.2 — August 2022** (supersedes v1.0 Aug-2021 and v1.1 Mar-2022). Filename `CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF`. Published at `media.defense.gov`.

**Threat model (the document organizes by threat, not just control):**
1. Supply-chain compromise (third-party images, registries, dependencies, K8s upstream).
2. Malicious threat actor (RCE, container escape, lateral movement).
3. Insider threats (admin, developer, vendor).

**Specific controls beyond the obvious PSS / NetworkPolicy / RBAC / audit:**

| § | Requirement | Mechanism |
|---|---|---|
| 2.1.1 | **Scan every image** for vulns, malware, misconfig **at build AND admission** | Two-stage: registry scan + admission webhook |
| 2.1.2 | **Image signing required** — only signed images admitted | Cosign / Notary v2; admission verifies |
| 2.1.3 | **Private registry only** in production; **air-gap mirror** required for classified | Zot/Harbor; pull-through cache disallowed at IL5+ |
| 2.2.x | **Immutable container filesystem** (`readOnlyRootFilesystem: true`) | Already in helmworks baseline |
| 2.2 | **Non-root, distroless or minimal base** | UBI-micro / distroless / chainguard |
| 3.x | **Encrypt etcd at rest** with KMS provider (not just `aescbc`) | KMSv2 + HSM-backed KEK |
| 3.x | **Separate control plane network** from worker network | Cilium ClusterMesh / dedicated VLAN |
| 4.x | **Audit log retention ≥ 1 year**, off-cluster, **tamper-evident** | Vector → S3 Object Lock / WORM |
| 4.x | **Audit policy** must capture all `RequestResponse` for Secrets/ConfigMaps/RBAC mutations | Specific audit-policy.yaml shape |
| 5.x | **Patch management cadence**: critical CVE in ≤ 30 days, high in ≤ 90 | Renovate + admission denial of stale digests |
| 6.x | **Periodic threat-hunt** via runtime-detection telemetry | Falco / Tetragon |

**NIST 800-53 mapping:** SI-3, SI-4, SI-7, SC-7, SC-8, SC-12, SC-13, SC-28, AC-3, AC-4, AC-6, AU-2/3/4/9/11/12, CM-2/3/5/7/8, IA-2, RA-5, SA-10/11/12.

## 2. DISA STIG for Kubernetes (V2R3, 2024-06-25)

| STIG ID | Severity | Requirement |
|---|---|---|
| **V-242381** | High | Default ServiceAccount must NOT be used |
| **V-242383** | High | User-managed resources must NOT be in `kube-system` |
| **V-242400** | High | Latest tag forbidden |
| **V-242414** | Medium | hostPath denied |
| **V-242415** | Medium | Secrets must be in Secret objects, not env values |
| **V-242417** | Medium | Pods must run as non-root |
| **V-242442** | Medium | Pull policies must be `Always` for `:latest`; `IfNotPresent` only with digest pin |
| **V-242443** | High | FIPS 140-2/3 mode required |
| **V-245540** | High | TLS for all ingress; minimum TLS 1.2 (FedRAMP-High wants 1.3) |
| **V-254800** | High | PodSecurityPolicy / PSS enforcement = `restricted` |
| **V-254801** | High | Resource quotas enforced |

**NIST mapping:** AC-2/3/6, AU-3/9/12, CM-6/7, IA-5, SC-8/12/13/17/28, SI-7.

## 3. DoD CC SRG Impact Levels

| IL | Data | FedRAMP equiv | K8s deltas |
|---|---|---|---|
| **IL2** | Public / non-CUI | FedRAMP Moderate | CIS K8s benchmark; commercial cloud OK |
| **IL4** | CUI, mission-support | FedRAMP Moderate + DoD overlay | DoD overlay: CNSSI 1253, dedicated tenancy preferred, US-only ops |
| **IL5** | CUI national-security, unclassified mission-critical | FedRAMP High + DoD IL5 overlay | Dedicated infra, FIPS 140-3 end-to-end, DISA-authorized CSO, US-only personnel/data, CAC/PIV admin auth, separate cluster from IL4, CNAP/BCAP routing |
| **IL6** | Classified up to SECRET | n/a | SIPRNet, hardware-rooted attestation (TPM 2.0 / Caliptra), SCIF physical hosting, NSA Type-1 crypto, classified-air-gap network |

## 4. DoD IronBank Container Hardening

1. Approved bases: RHEL UBI8/9-micro/minimal, Chainguard, distroless, IronBank-derived.
2. CVE thresholds: **Critical=0, High=0** (with documented waiver only).
3. SBOM: **CycloneDX 1.4+** preferred, SPDX 2.3 accepted, attached as cosign attestation.
4. Cosign sig: keyless via Fulcio with DoD PKI roots, OR keyed with HSM-resident key.
5. STIG hardening artifacts: OpenSCAP results attached as cosign attestation.
6. `hardening_manifest.yaml` listing every CVE accepted.
7. Two-person review; published at `registry1.dso.mil`.
8. License compliance: every component LICENSE field populated.
9. Continuous re-scan; image fails build on new CVE crossing threshold.
10. Provenance: SLSA Level 2 minimum, L3 for new submissions in 2025+.

## 5. CISA / NIST SSDF + EO 14028

- **EO 14028** — Improving the Nation's Cybersecurity, May 2021.
- **NIST SP 800-218 SSDF v1.1** — Feb 2022.
- **OMB M-22-18 / M-23-16** — federal supplier self-attestation.

K8s-layer requirements:
- SBOM (CycloneDX/SPDX) attached to every image.
- Provenance attestation (in-toto + SLSA) signed.
- Vulnerability disclosure (VEX document, OpenVEX 0.2.0).
- Multi-factor admin (CAC/PIV).
- Encryption at rest + in transit.

## 6. Sigstore — cosign / rekor / fulcio (air-gap)

Air-gap deployment pattern:
1. Private rekor (Trillian + MySQL) — seed from upstream rekor for verification of pre-existing artifacts.
2. Private fulcio with offline DoD CA root (HSM-resident, M-of-N quorum).
3. Hardware tokens for build/release signing: YubiHSM 2 FIPS (cert #4738), AWS CloudHSM, Thales Luna.
4. Offline trust root distributed via TUF — `cosign initialize --root <air-gap-root.json> --mirror <internal-tuf-mirror>`.
5. **Zot is the de-facto choice for air-gap registries** in DoD environments (CNCF-graduated, OCI 1.1, FIPS-mode build, sync extension).
6. Verification at admission: cosign-verify or **Sigstore Policy Controller** or **Kyverno verifyImages**.

## 7. SLSA 1.0

| Level | Requirements |
|---|---|
| **L1** | Provenance exists |
| **L2** | Provenance signed by build platform; hosted build service |
| **L3** | Build isolation; tamper-resistant provenance; secrets isolated per build |

- FedRAMP Moderate ⇒ SLSA L2 (per OMB M-22-18 / M-23-16).
- FedRAMP High ⇒ SLSA L3.
- IL5+ ⇒ SLSA L3 + hardware-attested build worker.

Format: in-toto Statement with SLSA v1.0 Provenance predicate, DSSE-signed.

## 8. OPA Gatekeeper vs Kyverno

| Policy | Gatekeeper template | Kyverno policy |
|---|---|---|
| no public images | `K8sAllowedRepos` | `restrict-image-registries` |
| no privileged | (deprecated) | `disallow-privileged-containers` |
| no host paths | `K8sPSPHostFilesystem` | `disallow-host-path` |
| signed images | (custom external-data) | **`verifyImages`** (first-class) |
| seccomp RuntimeDefault | `K8sPSPSeccomp` | `restrict-seccomp` |

**DoD/FedRAMP usage:** Gatekeeper has the longer history (RH OpenShift, DISA STIG references); Kyverno has overtaken for image-signature verification (verifyImages first-class). Large DoD platforms run BOTH.

## 9. Falco runtime detection rules (compliance-relevant)

- **Container drift detected (open+create)** — gold-standard control for image-immutability complementing readOnlyRootFilesystem (SI-7).
- **Write below etc / root / binary dir** — CM-3, SI-7.
- **Unexpected outbound connection** — paired with per-workload allowlist (SC-7).
- **Read sensitive file untrusted** — AC-6, AU-2.
- **Run shell untrusted** — CM-7.
- **Contact K8s API Server From Container** — AC-3, AC-4.
- **Change thread namespace** — container-escape detection (SI-4, SC-7).

## 10. FIPS 140-3 in Kubernetes

| Layer | Requirement |
|---|---|
| Kernel | RHEL 8/9 FIPS, Ubuntu Pro FIPS, Bottlerocket FIPS, AKS/EKS FIPS node groups |
| OpenSSL | FIPS-validated provider 3.0 (cert #4282) |
| Go | `microsoft/go` (BoringSSL CMVP) or `go-toolset` (boringcrypto); Go 1.24+ native `GODEBUG=fips140=on` |
| Java | OpenJDK + Bouncy Castle FIPS, Amazon Corretto Crypto Provider |
| Python | RHEL FIPS-mode Python (system OpenSSL) |
| Node.js | `--enable-fips` startup flag |
| Rust | aws-lc-fips (CMVP-validated) |
| TLS | TLS 1.2 minimum FIPS suites; TLS 1.3 with NIST-approved (`TLS_AES_256_GCM_SHA384`, `TLS_AES_128_GCM_SHA256`). NO chacha20-poly1305 |
| At-rest | FIPS KMS (AWS KMS FIPS endpoints, GovCloud, Azure Key Vault FIPS HSM, Thales Luna). KMSv2 in K8s |
| Containers | FIPS-mode base (UBI8/9 FIPS, `cgr.dev/chainguard/...-fips`) |

## 11. Industry-best Helm chart primitives

| Source | Primitive worth adapting |
|---|---|
| Bitnami common | `common.images.image` (image string with digest fallback), `common.tplvalues.render`, `common.errors.*`, `common.warnings.rollingTag` |
| bjw-s common | **Multi-controller** (one chart → many Deployments/StatefulSets/CronJobs by key); persistence map; service map |
| Vault Helm | Injector sidecar pattern (`vault.hashicorp.com/agent-inject`); CSI provider; audit storage as first-class |
| External Secrets | ClusterSecretStore + ExternalSecret CR (canonical Akeyless integration) |
| cert-manager | ClusterIssuer/Issuer abstraction; ApprovalPolicy CRDs |
| Falco | Multi-source rule ConfigMap merge |
| Kyverno | Policy library as separate chart; verifyImages first-class |

## 12. Air-gap-specific tooling

- **Hauler** (`hauler.dev`) — single-binary; produces a "haul" tarball of OCI images + Helm charts + files + SBOMs; serves as registry on air-gap side. **De-facto choice for SCIF transport.**
- **`oras`** — push/pull arbitrary OCI artifacts (Helm, SBOMs, OPA bundles, Falco rules).
- **Zot sync extension** — pull configurable artifact lists from upstream on schedule.
- **Pulp 3** — Red Hat's content-management for container, RPM, deb, helm, ansible, ostree.
- **`crane mutate` / `image-relocation`** — rewrite image refs in YAMLs/Helm charts.

---

## Implementation wave priority

1. `_compliance_supplychain.tpl` — SBOM/SLSA/cosign/CVE
2. `_compliance_fips.tpl` — FIPS 140-3 enforcement
3. `_compliance_admission.tpl` — Kyverno verifyImages + Gatekeeper Constraint
4. `_compliance_runtime.tpl` — Falco rules ConfigMap
5. `_compliance_airgap.tpl` extensions — registry allowlist + relocation
6. `_compliance_il.tpl` — IL2/IL4/IL5/IL6 typed switch
7. `_compliance_stig.tpl` — STIG ID mapping + assertions
8. bjw-s style multi-controller refactor (long-term)

## Cross-cutting NIST 800-53 control coverage extensions

| Control | Net-new helper |
|---|---|
| AC-2 | `rbac.serviceAccountTokenAudience` |
| AU-9(2) | `audit.tamperEvident` (WORM annotation requirement) |
| CM-3 | `runtime.driftPolicy` (Falco drift rule) |
| CM-7(5) | `admission.allowList` (deny-by-default at admission) |
| CM-8 | `supplychain.sbom` (SBOM digest requirement) |
| CM-10 | `supplychain.licenses` (license enumeration) |
| IA-5(1) | `secrets.externalStore` (ExternalSecret-only) |
| IA-7 | `fips.validate` (FIPS 140-3) |
| RA-5 | `supplychain.scanResult` (scan digest annotation) |
| SA-10 | `slsa.validate` (L≥2) |
| SA-11 | `supplychain.testResults` |
| SA-12 | `supplychain.provenance` (in-toto) |
| SC-7(7) | `network.egressAllowlist` |
| SC-8(1) | `network.tlsRequired` (mTLS labels) |
| SC-12(2) | `attestation.hsm` (HSM-resident key) |
| SC-17 | `attestation.dodPki` (DoD PKI roots IL5+) |
| SC-28(1) | `storage.fipsKms` (FIPS KMS-backed CSI) |
| SI-3 | `runtime.malwareScan` |
| SI-4(2) | `runtime.falcoRules` |
| SI-7(6) | `attestation.signed` (cosign required) |
| SR-3 | `supplychain.attestation` |
| SR-4(3) | `supplychain.provenance` |
| SR-11(2) | `supplychain.tampering` |

---

## Authoritative URLs

- NSA K8s Hardening v1.2: `media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF`
- DISA STIGs: `public.cyber.mil/stigs/downloads/`
- DoD CC SRG v1r4: `dl.dod.cyber.mil/wp-content/uploads/cloud/SRG/`
- IronBank: `repo1.dso.mil/dsop`, `ironbank.dso.mil`
- DoD Container Hardening Guide: `dl.dod.cyber.mil/wp-content/uploads/devsecops/pdf/DevSecOps_Enterprise_Container_Hardening_Guide_1.2.pdf`
- NIST SP 800-218 SSDF: `nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-218.pdf`
- EO 14028: `whitehouse.gov/briefing-room/presidential-actions/2021/05/12/executive-order-on-improving-the-nations-cybersecurity/`
- OMB M-22-18 / M-23-16
- Sigstore: `sigstore.dev`; cosign spec: `github.com/sigstore/cosign/tree/main/specs`
- SLSA v1.0: `slsa.dev/spec/v1.0/`
- Falco rules: `github.com/falcosecurity/rules`
- Gatekeeper library: `github.com/open-policy-agent/gatekeeper-library`
- Kyverno policies: `github.com/kyverno/policies`
- FIPS 140-3 / CMVP: `csrc.nist.gov/projects/cryptographic-module-validation-program`
- NIST SP 800-53r5: `nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf`
- CIS Kubernetes Benchmark: `cisecurity.org/benchmark/kubernetes`
- Hauler: `hauler.dev`
- Zot: `zotregistry.dev`
- Pulp: `pulpproject.org`
- OCI Image-Spec 1.1: `github.com/opencontainers/image-spec/blob/main/spec.md`
