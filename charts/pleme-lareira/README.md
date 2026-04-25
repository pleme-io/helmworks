# pleme-lareira

> *lareira* — Brazilian-Portuguese for *hearth* / *fireplace*; the warm
> central place where a family gathers. Library chart for home-services
> workloads on a pleme-io cluster.

Layered specialization of [`pleme-lib`](../pleme-lib) for the homelab
shape: family / household / single-author / creative-pro services that are
mostly idle, want SSO, want simple LAN-side ingress with cert-manager TLS,
and need restic backups + breathability defaults to fit on a 32 GB
single-node K3s.

## What it adds on top of pleme-lib

| Helper | Purpose |
|---|---|
| `pleme-lareira.enabled` | Master toggle helper. Every consumer chart guards its templates with `{{- if include "pleme-lareira.enabled" . }}` so the default render is empty — opt-in deployment. |
| `pleme-lareira.ingress` | LAN-side `Ingress` with cert-manager TLS + auto-merged Authentik forward-auth annotations. |
| `pleme-lareira.authentik.annotations` | nginx-ingress forward-auth annotations targeting the Authentik embedded outpost. |
| `pleme-lareira.cloudflared.serviceAnnotations` | Annotations the host-side cloudflared reconciler reads to populate tunnel ingress entries. |
| `pleme-lareira.pvc` (+ `.volume`, `.volumeMount`) | ZFS-backed PersistentVolumeClaim via local-path-provisioner with optional node pinning. |
| `pleme-lareira.restic.cronjob` | Backup CronJob mounting the same PVC, pushing to a restic repo (typically Cloudflare R2 free tier). Optional weekly verify CronJob. |
| `pleme-lareira.alerts.common` | Baseline `PrometheusRule` — PodDown, PodRestarting, PodOOMKilled, PvcUsedHigh (when persistence enabled), ResticBackupStale + ResticBackupFailing (when backup enabled). |
| `pleme-lareira.breathability.cron` | KEDA `ScaledObject` with cron trigger — wake during the day, sleep at night. Composes with pleme-lib's NATS-driven trigger. |
| `pleme-lareira.serviceAnnotations` | Combine cloudflared tunnel annotations with user-provided service annotations. |

## What it doesn't add

- **No new Deployment / Service / ServiceMonitor / NetworkPolicy / PDB / HPA
  primitives.** Those come from pleme-lib unchanged.
- **No SSO server.** Authentik is deployed as a separate infra chart; this
  chart only wires consumer ingresses to forward-auth against it.
- **No tunnel daemon.** Cloudflared runs on the host (NixOS module) for
  ownership reasons; this chart only stamps Service annotations the
  host-side reconciler reads.
- **No backup target.** restic CronJobs need a `Secret` containing the
  repository URL + creds; provision that out of band (SOPS, External
  Secrets, etc.).

## Usage in a consumer chart

`charts/<service>/Chart.yaml`:

```yaml
apiVersion: v2
name: <service>
type: application
version: 0.1.0

dependencies:
  - name: pleme-lib
    version: "~0.5.0"
    repository: "file://../pleme-lib"
  - name: pleme-lareira
    version: "~0.1.0"
    repository: "file://../pleme-lareira"
```

`charts/<service>/values.yaml` (always start with `enabled: false`):

```yaml
enabled: false   # opt-in
image:
  repository: ghcr.io/example/myapp
  tag: latest
service:
  ports:
    - name: http
      port: 8080
      targetPort: http
ingress:
  enabled: false
authentik:
  enabled: false
persistence:
  enabled: false
backup:
  enabled: false
```

`charts/<service>/templates/deployment.yaml`:

```yaml
{{- if include "pleme-lareira.enabled" . }}
{{- include "pleme-lib.deployment" . }}
{{- end }}
```

`charts/<service>/templates/service.yaml`:

```yaml
{{- if include "pleme-lareira.enabled" . }}
{{- include "pleme-lib.service" . }}
{{- end }}
```

`charts/<service>/templates/ingress.yaml`:

```yaml
{{- if include "pleme-lareira.enabled" . }}
{{- include "pleme-lareira.ingress" . }}
{{- end }}
```

`charts/<service>/templates/pvc.yaml`:

```yaml
{{- if include "pleme-lareira.enabled" . }}
{{- include "pleme-lareira.pvc" . }}
{{- end }}
```

`charts/<service>/templates/backup.yaml`:

```yaml
{{- if include "pleme-lareira.enabled" . }}
{{- include "pleme-lareira.restic.cronjob" . }}
{{- end }}
```

`charts/<service>/templates/breathability.yaml`:

```yaml
{{- if include "pleme-lareira.enabled" . }}
{{- include "pleme-lareira.breathability.cron" . }}
{{- include "pleme-lib.breathability" . }}
{{- end }}
```

`charts/<service>/templates/prometheusrule.yaml`:

```yaml
{{- if include "pleme-lareira.enabled" . }}
{{- include "pleme-lareira.alerts.common" . }}
{{- end }}
```

`charts/<service>/templates/networkpolicy.yaml`:

```yaml
{{- if include "pleme-lareira.enabled" . }}
{{- include "pleme-lib.networkpolicy" . }}
{{- end }}
```

That's the entire boilerplate per service. The diversity is in `values.yaml`.

## Default-off rationale

A homelab cluster running 30+ services with everything enabled-by-default
turns FluxCD into a footgun: one merge to main and rio is suddenly trying
to schedule everything. Default-off means new charts can land in the
HelmRepository without running until a HelmRelease explicitly flips
`values.enabled: true`. Each service is a deliberate decision.

## See also

- `pleme-lib` — primitives this chart layers on
- `pleme-microservice` / `pleme-worker` / `pleme-cronjob` — generalist
  application charts pleme-lareira does *not* replace
- Reference cluster: [`pleme-io/k8s/clusters/rio`](../../../k8s/clusters/rio)
