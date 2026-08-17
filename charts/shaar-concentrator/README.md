# shaar-concentrator (PRIVATE)

The Shaar VPN concentrator's k8s workload as a typed Helm chart — the reproducible,
versioned replacement for the hand-`kubectl`'d raw manifests in
`akeyless-vpn/deploy/concentrator/`.

> **PRIVATE + host-free (skunkworks).** Shaar STAYS PRIVATE. This chart is
> **NOT** wired into the public AUTO-RELEASE — its `Chart.yaml` carries
> `annotations: { pleme.io/oci-auto-release: "false" }`, so forge's
> `discover_charts` skips it and the helmworks auto-release never publishes it to
> `oci://ghcr.io/pleme-io/charts` (the same mechanism cartorio / lacre /
> openclaw-\* use). It is rendered `helm template | kubectl apply`-style **from
> the pleme-io side** into its own `shaar` namespace on borrowed (guest) ground.
> No host-facing artifacts; no FluxCD/operator wiring for the workload; no
> account-id / EIP / reach-CIDRs committed here.

## The shape

`shaar-concentrator` runs as a **hostNetwork pod** so it binds the WireGuard UDP
port on the **node's own address** (Camelot Mode-1: the single k3s node's EIP).
Clients dial that endpoint, lease an **akeyless-identity-gated** short-TTL WG
credential, and reach the cluster's k8s API + services **privately through the
tunnel**. Only the hardened WG UDP port is ever public.

The chart renders four workload objects + two helpers:

| Object | Rendered by | Notes |
|---|---|---|
| `Deployment shaar-concentrator` | `templates/deployment.yaml` (direct) | hostNetwork, NET_ADMIN, root, WG UDP + `/sync` + admin ports, PVC-backed `/var/lib/shaar` |
| `Service shaar-concentrator-sync` | `templates/service.yaml` (direct) | the `/sync` webhook (8443); optional admin port (opt-in) |
| `ConfigMap shaar-concentrator-config` | `templates/configmap.yaml` | `concentrator.yaml` from the typed surface; **secret refs, no plaintext** |
| `PersistentVolumeClaim shaar-concentrator-state` | `templates/pvc.yaml` (direct) | Ed25519 signing key + receipt chain (RWO) |
| `ServiceAccount` + `NetworkPolicy` | `templates/other.yaml` → `pleme-lib.*` | SA created; NetworkPolicy OFF by default |
| `MemoryBand` / `CpuBand` | `templates/other.yaml` → `pleme-lib.breatheBand` | optional, vertical-only, default OFF |

## The values surface (key knobs)

| Key | What | Default |
|---|---|---|
| `image.{repository,tag,pullPolicy}` | the private `ghcr.io/pleme-io/shaar-concentrator` image | `amd64-latest` (pin an exact AUTOBUMP tag) |
| `localImport` | `true` ⇒ `pullPolicy: Never` (locally-imported image) | `false` |
| `imagePullSecrets` | private-GHCR pull creds | `[{name: ghcr-pleme-io}]` |
| `nodeSelector` / `tolerations` | pin to one node; tolerate the breathe pool taint | unpinned / breathe taint |
| `pool.cidr` | the `/32` client address pool | `10.99.0.0/24` |
| `listen_port` | the server WireGuard UDP port | `51822` |
| `public_endpoint` | `ip:port` in every lease; empty ⇒ IMDS self-discovery | `""` |
| `reach.targetCidrs` | **REQUIRED** — the server-owned reach grant (k8s API + pod/svc CIDRs) | `[]` (per-deploy) |
| `leaseTtlSecs` / `gcIntervalSecs` | lease + GC tuning | `3600` / `60` |
| `engine` | `kernel` (fast) or `userspace` (portable) | `kernel` |
| `selfMasquerade` | own source-NAT for pool egress | `true` |
| `tunnelName` | base WG interface name | `shaar` |
| `identity.leaseQuota` | per-identity concurrent-lease cap (blast radius) | `""` (unlimited) |
| `identity.reachCeilings` | per-principal reach clamps (least-privilege) | `{}` |
| `webhook.port` | the `/sync` webhook port (Service + bind) | `8443` |
| `admin.{enabled,bind,expose,servicePort}` | the operator admin API | on, localhost, not exposed |
| `secretRef.{name,credsKey,tokenKey}` | the k8s Secret holding the two bearers | `shaar-concentrator-creds` |
| `state.{pvcSize,storageClassName}` | the state PVC | `1Gi` / default SC |
| `resources` | container requests/limits | 50m/64Mi → 500m/256Mi |
| `breathe` | optional MemoryBand/CpuBand (vertical only) | OFF |

`values.schema.json` is `additionalProperties: false` everywhere — a misspelled
or unknown key is an **install-time error**, not a silently-dropped no-op.

## Secrets — no plaintext, ever

`admin.token` and `webhook_creds` are **never** inline in the chart. The
`ConfigMap` carries only the `SecretRef::Env` *reference* (`kind: env, var: …`),
and the container reads the actual bearers from env vars injected via
`valueFrom.secretKeyRef` from the `secretRef` Secret:

- `secretRef.credsKey` → env `SHAAR_CONCENTRATOR_CREDS` (the `/sync` bearer)
- `secretRef.tokenKey` → env `SHAAR_ADMIN_TOKEN` (the admin bearer; injected only
  when `admin.enabled`)

Create the Secret out-of-band (e.g. a cofre `SecretRef` materialization):

```bash
kubectl -n shaar create secret generic shaar-concentrator-creds \
  --from-literal=webhook-creds=<sync-bearer> \
  --from-literal=admin-token=<admin-bearer>
```

## Deploy

```bash
kubectl create namespace shaar   # our own footprint (get-in-and-isolate)

# render + apply from the pleme-io side (no committed host coords):
helm template shaar charts/shaar-concentrator -n shaar \
  -f my-shaar-values.yaml \        # reach CIDRs + pinned image tag + node pin
  | kubectl -n shaar apply -f -
```

See `values-example.yaml` for a sample override (HOST-FREE placeholders; NOT a
committed production config). The full plan (image → config → the akeyless
custom-producer → deploy → client cutover) lives in
`akeyless-vpn/deploy/concentrator/README.md` + `docs/SHAAR-CAMELOT-BINDING.md`.

## Honest gaps

- **hostNetwork ⇒ Deployment/Service/PVC authored directly, not via
  `pleme-lib.deployment`.** pleme-lib's `_deployment.tpl` / `_statefulset.tpl` do
  **not** render `hostNetwork` / `dnsPolicy` (they only reference `hostNetwork` in
  the compliance *validator*, to forbid it under a baseline). hostNetwork is
  load-bearing here — the WG server MUST bind the node's own address — so the pod
  spec is hand-authored while reusing pleme-lib helpers (`fullname` / `namespace`
  / `labels` / `selectorLabels`) for label consistency. The load-bearing fleet
  fix would be to add an opt-in `hostNetwork` / `dnsPolicy` knob to
  `pleme-lib._deployment.tpl` (+ statefulset); until then this chart owns its pod
  spec. Not done here to keep scope to this chart (a pleme-lib change touches
  ~10 Deployment consumers + needs a byte-diff proof of no drift).
- **NetworkPolicy is OFF by default and honestly so.** Kubernetes NetworkPolicy
  does **not** govern hostNetwork pod traffic in most CNIs (the pod uses the
  node's netns). A deny-all here would be a misleading no-op. Node-level
  firewalling (nftables / cloud security-group) is the real control for a
  hostNetwork WG server. The toggle is retained for a future non-hostNetwork
  variant.
- **breathe is vertical-only (Memory/Cpu), no ReplicaBand/spot.** A stateful
  hostNetwork WG server pinned to one node with an RWO PVC is a legit
  skip-breathe on the replica + spot axes — running two concentrators would fight
  over the host UDP port + the RWO PVC. `strategy: Recreate` + `replicaCount: 1`
  enforce the singleton.
- **admin API exposure.** `admin.bind` defaults to `127.0.0.1:8088`
  (trusted-interface posture). A localhost bind is not reachable via a ClusterIP
  Service on a hostNetwork pod, so `admin.expose` is OFF by default — operator
  admin reach is `kubectl exec` / a node-local tunnel. Exposing the admin port on
  the Service requires *also* widening `admin.bind` to a Service-reachable
  address, and must never sit on a public path.
- **pleme-lib version pin.** `>=0.33.0` (floor, per the helmworks floor-only
  convention) — the same floor the twin `lareira-fortigate-gateway` pins for
  values-driven `securityContext.capabilities.add` + honest `runAsUser: 0`. The
  in-tree pleme-lib (0.40.1) is vendored at release time; the ServiceAccount +
  breatheBand named templates this chart consumes are stable across that range.
- **The akeyless custom-producer (P4) is out of chart scope** — registering the
  auth-method / access-role / custom WG producer in the akeyless tenant is
  outward-facing account provisioning done out-of-band by the operator (see
  `akeyless-vpn/deploy/concentrator/README.md`). The chart renders only the
  in-cluster workload the producer's `/sync` URL points at.
