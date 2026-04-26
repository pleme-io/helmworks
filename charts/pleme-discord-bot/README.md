# pleme-discord-bot

Helm chart that runs ONE [`blackmatter-discord`][bd] bot crate as a
Kubernetes Deployment.

[bd]: https://github.com/pleme-io/blackmatter-discord

## Architecture

```
blackmatter-discord/crates/bm-discord-<name>
       │
       ▼ Nix → Docker image
       │
ghcr.io/pleme-io/bm-discord-<name>:<tag>
       │
       ▼ pleme-discord-bot (this chart)
       │
   Deployment(replicas=1, strategy=Recreate)
       │ envFrom: discord-<name>-token (Secret)
       │ optional: /etc/discord/commands.json (ConfigMap from pangea-discord/terraform)
       ▼
    Bot connects gateway, registers commands, dispatches.
```

## Prerequisites

1. The bot binary published as a container image (substrate's
   rust-to-docker recipe).
2. A Kubernetes Secret named `discord-<botName>-token` (or override
   via `tokenSecret.name`) containing the raw bot token under the key
   `DISCORD_BOT_TOKEN`. Typically managed via ExternalSecrets
   pulling from Akeyless.
3. (Optional) A ConfigMap rendered by `terraform apply` against
   pangea-discord's `discord_application_command` resources, mirrored
   into the cluster for engine-side validation against `Bot::commands()`.

## Minimal install

```yaml
# values.yaml
botName: example
image:
  repository: ghcr.io/pleme-io/bm-discord-example
  tag: 0.1.0
```

```sh
helm install discord-example pleme-discord-bot -f values.yaml
```

## With command manifest

```yaml
botName: example
image:
  repository: ghcr.io/pleme-io/bm-discord-example
  tag: 0.1.0
commandsManifest:
  enabled: true
  configMapName: discord-example-commands  # rendered by terraform
```

## Why one chart per bot

Bots are independent applications: separate tokens, separate guild scopes,
separate failure modes. A single Helm release per bot keeps rollouts and
rollbacks scoped — and the strategy is `Recreate` because Discord's
gateway requires one shard per IDENTIFY (parallel pods would race).

## See also

- `blackmatter-discord` — bot fleet workspace
- `discord-rs` — Rust SDK
- `pangea-discord` — Ruby DSL declaring command shapes
- `discord-terraform-resources` — TOML catalog (source of truth)
