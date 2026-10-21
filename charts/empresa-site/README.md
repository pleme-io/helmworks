# empresa-site

One company's static site on an engenho node. The chart renders a Deployment, a Service, a placeholder page and a `serve-config` ConfigMap. It renders no Ingress and no tunnel.

## Server

The server is hanabi (`ghcr.io/pleme-io/hanabi`), the house static server. The default tag is the chart `appVersion`. A `latest` tag fails the schema. The container runs non-root with a read-only root filesystem, drops all capabilities, mounts no service account token and execs no probe.

The hanabi config comes from the chart. It binds `service.port` for content and `service.port + 1` for health, so both ports are unprivileged.

## Content

| `content.placeholder.enabled` | Container image | Content |
|---|---|---|
| `true` (default) | `server.image` | a built-in page from a ConfigMap, mounted at `/app/static` |
| `false` | `content.image` | the site image; it must run hanabi, read `/etc/hanabi/config.yaml` and serve `/app/static` |

`content.image.repository` and `content.image.tag` are required when the placeholder is off.

## Path prefix

`pathPrefix` defaults to `/`. With a prefix such as `/acme`, the placeholder serves at `/` and at `/acme/`. A content image serves at `/` only, so `serve-config` marks the mapping `stripPrefix: true`: the exposure layer strips the prefix before it forwards.

## serve-config

The ConfigMap `<release>-empresa-site-serve-config` carries the label `pleme.io/serve-config: "true"` and one key, `serve.json`. It states the hosts, the Service, and one mount: the path, the Service target and `stripPrefix`. The exposure layer reads it. The chart applies nothing to Tailscale.

## Values

| Key | Default | Meaning |
|---|---|---|
| `company` | required | slug |
| `hosts` | required | hostnames the site answers to |
| `pathPrefix` | `/` | prefix the site also answers under |
| `content.image.repository`, `content.image.tag` | empty | static site image |
| `content.placeholder.enabled` | `true` | built-in page |
| `server.image.repository`, `server.image.tag` | hanabi, `appVersion` | server image |
| `server.pullPolicy` | `IfNotPresent` | |
| `service.port` | `8080` | 1024 to 65534 |
| `resources` | 10m / 16Mi requests, 200m / 64Mi limits | |
| `nodeSelector` | `{}` | |
| `replicaCount` | `1` | |
| `imagePullSecrets`, `nameOverride`, `fullnameOverride` | empty | |

## Schema

`values.schema.json` is generated from `schemas/src/empresa_site.rs`. Regenerate it with `cargo run --manifest-path schemas/Cargo.toml` from the repo root. `nix flake check` fails when the committed file is stale.

## Example

```sh
helm template acme charts/empresa-site -n sites -f examples/empresa-site.yaml
```
