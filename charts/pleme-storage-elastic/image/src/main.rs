//! `pleme-storage-elastic` — PVC autosize watcher.
//!
//! Implements [`theory/BREATHABILITY.md` §V](https://github.com/pleme-io/theory):
//! keep watched PVCs at ~80% utilization, expand by `expand_factor`
//! (default 1.25) when triggered, never shrink. Hard ceiling at
//! `max_size` is the circuit breaker.
//!
//! Single-shot: enumerate PVCs → check usage via Prometheus → patch
//! when needed → exit. Driven by a CronJob in the chart's templates.

#![allow(clippy::missing_errors_doc, clippy::missing_panics_doc)]

use std::collections::BTreeMap;

use anyhow::{Context, Result};
use chrono::Utc;
use clap::Parser;
use k8s_openapi::api::core::v1::PersistentVolumeClaim;
use kube::{
    api::{Api, ListParams, Patch, PatchParams},
    Client,
};
use serde::Serialize;
use tracing::{error, info};

const ANNOTATION_LAST_EXPANSION: &str = "pleme.pleme.io/last-expansion-epoch";

#[derive(Parser, Debug)]
#[command(version, about = "PVC autosize watcher (theory/BREATHABILITY.md §V)")]
struct Args {
    /// Fraction of capacity that triggers expansion (0–1).
    #[arg(long, env, default_value_t = 0.80)]
    trigger_at: f64,

    /// Multiplier applied to current capacity on expansion.
    #[arg(long, env, default_value_t = 1.25)]
    expand_factor: f64,

    /// Hard ceiling per PVC; emits `PVCAtCeiling` if breached.
    /// Kubernetes-style quantity — e.g. `100Gi`, `1Ti`.
    #[arg(long, env, default_value = "100Gi")]
    max_size: String,

    /// Minimum interval between expansions of the same PVC (seconds).
    #[arg(long, env, default_value_t = 600)]
    cooldown_seconds: u64,

    /// If true, log only — don't patch anything.
    #[arg(long, env, default_value_t = false)]
    dry_run: bool,

    /// JSON array of namespace names to scan; `[]` → all namespaces.
    #[arg(long, env, default_value = "[]")]
    namespaces: String,

    /// JSON array of explicit `{namespace,name}` pairs; overrides selector.
    #[arg(long, env, default_value = "[]")]
    pvcs: String,

    /// JSON object label-selector (`{"matchLabels":{"k":"v"}}`).
    #[arg(long, env, default_value = "{}")]
    selector: String,

    /// Prometheus-compatible `/api/v1/query` endpoint for `kubelet_volume_stats_*`.
    #[arg(long, env)]
    usage_query_url: Option<String>,
}

#[derive(Serialize)]
#[serde(tag = "event")]
enum Event<'a> {
    PvcExpanding {
        namespace: &'a str,
        pvc: &'a str,
        from: &'a str,
        to: &'a str,
        ratio: f64,
        dry_run: bool,
    },
    PvcExpanded {
        namespace: &'a str,
        pvc: &'a str,
        from: &'a str,
        to: &'a str,
    },
    PvcInCooldown {
        namespace: &'a str,
        pvc: &'a str,
        since_seconds: i64,
    },
    PvcAtCeiling {
        namespace: &'a str,
        pvc: &'a str,
        capacity: &'a str,
        max: &'a str,
    },
    PvcMetricsMissing {
        namespace: &'a str,
        pvc: &'a str,
    },
    WatcherRunComplete {
        timestamp_epoch: i64,
        scanned: usize,
        expanded: usize,
        skipped_cooldown: usize,
        at_ceiling: usize,
    },
}

fn emit(ev: &Event<'_>) {
    // The chart's CronJob ships stdout through the kubelet → Vector →
    // VictoriaLogs path. Single JSON line per event keeps grep-ability.
    if let Ok(line) = serde_json::to_string(ev) {
        println!("{line}");
    }
}

#[derive(Debug)]
struct Target {
    namespace: String,
    name: String,
}

#[derive(Debug)]
struct PvcUsage {
    used: u64,
    capacity: u64,
}

#[derive(serde::Deserialize)]
struct ExplicitPvc {
    namespace: String,
    name: String,
}

#[derive(serde::Deserialize)]
struct LabelSelector {
    #[serde(rename = "matchLabels", default)]
    match_labels: BTreeMap<String, String>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .json()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,pleme_storage_elastic=debug".into()),
        )
        .init();

    let args = Args::parse();
    let client = Client::try_default()
        .await
        .context("failed to construct in-cluster Kubernetes client")?;

    let max_size_bytes: u64 = parse_size::Config::new()
        .with_binary()
        .parse_size(&args.max_size)
        .with_context(|| format!("max_size {:?} is not a valid quantity", args.max_size))?;

    let targets = enumerate_targets(&client, &args).await?;
    let mut counters = (0_usize, 0_usize, 0_usize, 0_usize); // scanned, expanded, cooldown, ceiling

    for t in &targets {
        counters.0 += 1;
        match process_one(&client, t, &args, max_size_bytes).await {
            Ok(Outcome::Expanded) => counters.1 += 1,
            Ok(Outcome::Cooldown) => counters.2 += 1,
            Ok(Outcome::AtCeiling) => counters.3 += 1,
            Ok(Outcome::BelowThreshold) | Ok(Outcome::MissingMetrics) | Ok(Outcome::DryRun) => {}
            Err(e) => error!(namespace = %t.namespace, pvc = %t.name, error = %e, "process_one failed"),
        }
    }

    emit(&Event::WatcherRunComplete {
        timestamp_epoch: Utc::now().timestamp(),
        scanned: counters.0,
        expanded: counters.1,
        skipped_cooldown: counters.2,
        at_ceiling: counters.3,
    });

    Ok(())
}

enum Outcome {
    Expanded,
    Cooldown,
    AtCeiling,
    BelowThreshold,
    MissingMetrics,
    DryRun,
}

async fn enumerate_targets(client: &Client, args: &Args) -> Result<Vec<Target>> {
    // Explicit PVC list wins.
    let explicit: Vec<ExplicitPvc> = serde_json::from_str(&args.pvcs)
        .with_context(|| format!("PVCS env var is not valid JSON: {}", args.pvcs))?;
    if !explicit.is_empty() {
        return Ok(explicit
            .into_iter()
            .map(|e| Target {
                namespace: e.namespace,
                name: e.name,
            })
            .collect());
    }

    // Otherwise: selector + namespace list scan.
    let namespaces: Vec<String> = serde_json::from_str(&args.namespaces)
        .with_context(|| format!("NAMESPACES env var is not valid JSON: {}", args.namespaces))?;
    let selector: LabelSelector = serde_json::from_str(&args.selector)
        .with_context(|| format!("SELECTOR env var is not valid JSON: {}", args.selector))?;

    let label_selector = if selector.match_labels.is_empty() {
        None
    } else {
        Some(
            selector
                .match_labels
                .iter()
                .map(|(k, v)| format!("{k}={v}"))
                .collect::<Vec<_>>()
                .join(","),
        )
    };

    let mut targets = Vec::new();
    let lp = label_selector
        .as_ref()
        .map(|s| ListParams::default().labels(s))
        .unwrap_or_default();

    if namespaces.is_empty() {
        let api: Api<PersistentVolumeClaim> = Api::all(client.clone());
        for pvc in api.list(&lp).await?.items {
            if let (Some(ns), Some(name)) =
                (pvc.metadata.namespace.clone(), pvc.metadata.name.clone())
            {
                targets.push(Target { namespace: ns, name });
            }
        }
    } else {
        for ns in namespaces {
            let api: Api<PersistentVolumeClaim> = Api::namespaced(client.clone(), &ns);
            for pvc in api.list(&lp).await?.items {
                if let Some(name) = pvc.metadata.name.clone() {
                    targets.push(Target { namespace: ns.clone(), name });
                }
            }
        }
    }

    Ok(targets)
}

async fn process_one(
    client: &Client,
    target: &Target,
    args: &Args,
    max_size_bytes: u64,
) -> Result<Outcome> {
    let api: Api<PersistentVolumeClaim> = Api::namespaced(client.clone(), &target.namespace);
    let pvc = api.get(&target.name).await?;

    let current_q = pvc
        .spec
        .as_ref()
        .and_then(|s| s.resources.as_ref())
        .and_then(|r| r.requests.as_ref())
        .and_then(|m| m.get("storage"))
        .map(|q| q.0.clone())
        .context("PVC has no spec.resources.requests.storage")?;
    let current_b = parse_size::Config::new()
        .with_binary()
        .parse_size(&current_q)
        .with_context(|| format!("PVC capacity {current_q:?} unparsable"))?;

    // Usage from Prometheus (or skip if unconfigured).
    let usage = match &args.usage_query_url {
        None => None,
        Some(url) => fetch_usage(url, &target.namespace, &target.name).await.ok(),
    };
    let Some(usage) = usage else {
        emit(&Event::PvcMetricsMissing {
            namespace: &target.namespace,
            pvc: &target.name,
        });
        return Ok(Outcome::MissingMetrics);
    };
    let ratio = if usage.capacity == 0 {
        0.0
    } else {
        usage.used as f64 / usage.capacity as f64
    };
    if ratio < args.trigger_at {
        return Ok(Outcome::BelowThreshold);
    }

    // Cooldown check via PVC annotation.
    if let Some(last_str) = pvc
        .metadata
        .annotations
        .as_ref()
        .and_then(|a| a.get(ANNOTATION_LAST_EXPANSION))
    {
        if let Ok(last) = last_str.parse::<i64>() {
            let since = Utc::now().timestamp() - last;
            if since < i64::try_from(args.cooldown_seconds).unwrap_or(i64::MAX) {
                emit(&Event::PvcInCooldown {
                    namespace: &target.namespace,
                    pvc: &target.name,
                    since_seconds: since,
                });
                return Ok(Outcome::Cooldown);
            }
        }
    }

    // Expansion math.
    #[allow(clippy::cast_precision_loss, clippy::cast_possible_truncation, clippy::cast_sign_loss)]
    let new_b: u64 = ((current_b as f64 * args.expand_factor).ceil()) as u64;
    if new_b > max_size_bytes {
        emit(&Event::PvcAtCeiling {
            namespace: &target.namespace,
            pvc: &target.name,
            capacity: &current_q,
            max: &args.max_size,
        });
        return Ok(Outcome::AtCeiling);
    }
    let new_q = bytes_to_gibibytes_ceil(new_b);

    emit(&Event::PvcExpanding {
        namespace: &target.namespace,
        pvc: &target.name,
        from: &current_q,
        to: &new_q,
        ratio,
        dry_run: args.dry_run,
    });

    if args.dry_run {
        return Ok(Outcome::DryRun);
    }

    // Patch spec.resources.requests.storage.
    let patch = serde_json::json!({
        "spec": { "resources": { "requests": { "storage": new_q } } }
    });
    api.patch(
        &target.name,
        &PatchParams::apply("pleme-storage-elastic"),
        &Patch::Merge(&patch),
    )
    .await
    .context("PVC storage patch failed")?;

    // Annotation for cooldown tracking.
    let now = Utc::now().timestamp().to_string();
    let ann_patch = serde_json::json!({
        "metadata": { "annotations": { ANNOTATION_LAST_EXPANSION: now } }
    });
    let _ = api
        .patch(
            &target.name,
            &PatchParams::default(),
            &Patch::Merge(&ann_patch),
        )
        .await;

    emit(&Event::PvcExpanded {
        namespace: &target.namespace,
        pvc: &target.name,
        from: &current_q,
        to: &new_q,
    });
    info!(
        namespace = %target.namespace,
        pvc = %target.name,
        from = %current_q,
        to = %new_q,
        "expanded"
    );
    Ok(Outcome::Expanded)
}

async fn fetch_usage(prom_url: &str, namespace: &str, pvc: &str) -> Result<PvcUsage> {
    let used_q = format!(
        r#"kubelet_volume_stats_used_bytes{{namespace="{namespace}",persistentvolumeclaim="{pvc}"}}"#
    );
    let cap_q = format!(
        r#"kubelet_volume_stats_capacity_bytes{{namespace="{namespace}",persistentvolumeclaim="{pvc}"}}"#
    );

    let used = prom_query_scalar(prom_url, &used_q).await?;
    let capacity = prom_query_scalar(prom_url, &cap_q).await?;

    Ok(PvcUsage {
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        used: used as u64,
        #[allow(clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        capacity: capacity as u64,
    })
}

async fn prom_query_scalar(base: &str, query: &str) -> Result<f64> {
    let url = format!("{}/api/v1/query", base.trim_end_matches('/'));
    let resp: serde_json::Value = reqwest::Client::new()
        .get(&url)
        .query(&[("query", query)])
        .timeout(std::time::Duration::from_secs(5))
        .send()
        .await?
        .json()
        .await?;
    let result = resp
        .pointer("/data/result/0/value/1")
        .and_then(serde_json::Value::as_str)
        .context("Prometheus response missing /data/result/0/value/1")?;
    Ok(result.parse()?)
}

fn bytes_to_gibibytes_ceil(b: u64) -> String {
    let gibi = 1_u64 << 30;
    let n = (b + gibi - 1) / gibi;
    format!("{n}Gi")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bytes_to_gibibytes_round_up() {
        assert_eq!(bytes_to_gibibytes_ceil(0), "0Gi");
        assert_eq!(bytes_to_gibibytes_ceil(1_073_741_824), "1Gi");          // exactly 1 GiB
        assert_eq!(bytes_to_gibibytes_ceil(1_073_741_825), "2Gi");          // 1 byte over
        assert_eq!(bytes_to_gibibytes_ceil(40 * 1_073_741_824), "40Gi");
    }

    #[test]
    fn expansion_math_picks_correct_target() {
        // 30Gi current, 1.25× → 38Gi (ceil(37.5))
        let current_b: u64 = 30 * (1_u64 << 30);
        let factor = 1.25_f64;
        #[allow(clippy::cast_precision_loss, clippy::cast_possible_truncation, clippy::cast_sign_loss)]
        let new_b: u64 = ((current_b as f64 * factor).ceil()) as u64;
        assert_eq!(bytes_to_gibibytes_ceil(new_b), "38Gi");
    }
}
