use helm_forge::values_schema::strict_schema_value;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;

type Open = BTreeMap<String, Value>;

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PlemeLibValues {
    pub image: Option<Image>,
    pub image_pull_secrets: Option<Vec<PullSecret>>,
    #[schemars(regex(pattern = "^$|^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"))]
    pub name_override: Option<String>,
    #[schemars(regex(pattern = "^$|^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"))]
    pub fullname_override: Option<String>,
    pub replica_count: Option<u32>,
    pub service_account: Option<ServiceAccount>,
    pub ports: Option<Vec<Value>>,
    pub service: Option<Open>,
    pub env: Option<Vec<Value>>,
    pub env_from: Option<Vec<Value>>,
    pub volume_mounts: Option<Vec<Value>>,
    pub volumes: Option<Vec<Value>>,
    pub resources: Option<Open>,
    pub health: Option<Health>,
    pub startup_probe: Option<StartupProbe>,
    pub pod_security_context: Option<Open>,
    pub security_context: Option<Open>,
    pub strategy: Option<Open>,
    pub termination_grace_period_seconds: Option<u32>,
    pub pod_annotations: Option<BTreeMap<String, String>>,
    pub node_selector: Option<BTreeMap<String, String>>,
    pub tolerations: Option<Vec<Value>>,
    pub affinity: Option<Open>,
    pub topology_spread_constraints: Option<Vec<Value>>,
    pub priority_class_name: Option<String>,
    pub init_containers: Option<Vec<Value>>,
    pub sidecars: Option<Vec<Value>>,
    pub command: Option<Vec<String>>,
    pub args: Option<Vec<String>>,
    pub additional_labels: Option<BTreeMap<String, String>>,
    pub lifecycle: Option<Open>,
    pub config_maps: Option<Vec<Value>>,
    pub downward_api: Option<DownwardApi>,
    pub annotations: Option<Open>,
    pub monitoring: Option<Monitoring>,
    pub autoscaling: Option<Autoscaling>,
    pub network_policy: Option<NetworkPolicy>,
    pub runtime: Option<Runtime>,
    pub access: Option<Access>,
    pub secret_refs: Option<Vec<SecretRef>>,
    pub kenshi: Option<Kenshi>,
    pub telemetry: Option<Telemetry>,
    pub placements: Option<Vec<Placement>>,
    pub external_secret: Option<ExternalSecret>,
    pub global: Option<Open>,
    pub shinka_migration: Option<Open>,
    pub shinka_wait: Option<Open>,
    pub preflight: Option<Open>,
    pub vm_scrape: Option<Open>,
    pub breathe: Option<Open>,
    pub cost_guard: Option<Open>,
    pub pdb: Option<Open>,
    pub compliance: Option<Open>,
    pub security: Option<Open>,
    pub attestation: Option<Open>,
    pub istio: Option<Open>,
    pub pod_monitor: Option<Open>,
    pub prometheus_rules: Option<Open>,
    pub limit_range: Option<Open>,
    pub resource_quota: Option<Open>,
    pub karpenter: Option<Open>,
    pub rbac: Option<Open>,
    pub priority_classes: Option<Open>,
    pub alerts: Option<Value>,
    pub auto_approve: Option<Value>,
    pub automount_service_account_token: Option<bool>,
    pub breathability: Option<Value>,
    pub concurrency_policy: Option<String>,
    pub config: Option<Value>,
    pub crossplane: Option<Value>,
    pub csi_provider: Option<Value>,
    pub data_lifecycle: Option<Value>,
    pub delivery: Option<Value>,
    pub ephemeral: Option<Value>,
    pub finops: Option<Value>,
    pub flux: Option<Open>,
    pub github_auth: Option<Value>,
    pub grafana: Option<Value>,
    #[serde(rename = "hostIPC")]
    pub host_ipc: Option<bool>,
    pub host_network: Option<bool>,
    #[serde(rename = "hostPID")]
    pub host_pid: Option<bool>,
    pub ingress: Option<Value>,
    pub jetstream: Option<Value>,
    pub jetstream_init: Option<Value>,
    pub observability: Option<Value>,
    pub park: Option<Value>,
    pub persistence: Option<Value>,
    pub pitr: Option<Value>,
    pub placement: Option<Value>,
    pub queue_worker: Option<Value>,
    pub resilience: Option<Value>,
    pub respiro: Option<Value>,
    pub scale_to_zero: Option<Value>,
    pub schedule: Option<String>,
    pub scrape_triad: Option<Value>,
    pub service_accounts: Option<Value>,
    pub statefulset: Option<Value>,
    pub trust: Option<Value>,
    pub update_strategy: Option<Value>,
    pub vm: Option<Value>,
    pub volume_claim_templates: Option<Vec<Value>>,
    pub webhook: Option<Value>,
    pub worker: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Image {
    pub repository: Option<String>,
    pub tag: Option<String>,
    #[schemars(regex(pattern = "^$|^sha256:[a-f0-9]{64}$"))]
    pub digest: Option<String>,
    pub pull_policy: Option<PullPolicy>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum PullPolicy {
    Always,
    IfNotPresent,
    Never,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct PullSecret {
    #[schemars(length(min = 1))]
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ServiceAccount {
    pub create: Option<bool>,
    pub annotations: Option<BTreeMap<String, String>>,
    pub name: Option<String>,
    pub automount_service_account_token: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(untagged)]
pub enum IntOrString {
    Int(u16),
    Name(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum ProbeType {
    HTTPGet,
    TCPSocket,
    Exec,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Health {
    pub battery: Option<bool>,
    pub r#type: Option<ProbeType>,
    pub path: Option<String>,
    pub ready_path: Option<String>,
    pub port: Option<IntOrString>,
    pub host: Option<String>,
    pub exec_command: Option<Vec<String>>,
    pub liveness_initial_delay: Option<u32>,
    pub liveness_period: Option<u32>,
    pub liveness_timeout: Option<u32>,
    pub liveness_failure_threshold: Option<u32>,
    pub readiness_initial_delay: Option<u32>,
    pub readiness_period: Option<u32>,
    pub readiness_timeout: Option<u32>,
    pub readiness_failure_threshold: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct StartupProbe {
    pub enabled: Option<bool>,
    pub path: Option<String>,
    pub port: Option<IntOrString>,
    pub host: Option<String>,
    pub initial_delay_seconds: Option<u32>,
    pub period_seconds: Option<u32>,
    pub failure_threshold: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct DownwardApi {
    pub enabled: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Monitoring {
    pub enabled: Option<bool>,
    pub port: Option<IntOrString>,
    pub path: Option<String>,
    pub interval: Option<String>,
    pub scrape_timeout: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Autoscaling {
    pub enabled: Option<bool>,
    pub min_replicas: Option<u32>,
    pub max_replicas: Option<u32>,
    #[serde(rename = "targetCPUUtilizationPercentage")]
    #[schemars(range(min = 1, max = 100))]
    pub target_cpu_utilization_percentage: Option<u8>,
    #[schemars(range(min = 1, max = 100))]
    pub target_memory_utilization_percentage: Option<u8>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum NetworkPolicyScope {
    Workload,
    Namespace,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct NetworkPolicy {
    pub enabled: Option<bool>,
    pub scope: Option<NetworkPolicyScope>,
    pub unpoliced: Option<bool>,
    pub unpoliced_reason: Option<String>,
    pub require_declaration: Option<bool>,
    pub allow_dns: Option<bool>,
    pub allow_prometheus: Option<bool>,
    pub prometheus_namespaces: Option<Vec<String>>,
    pub allow_egress_https: Option<bool>,
    pub additional_ingress: Option<Vec<Value>>,
    pub additional_egress: Option<Vec<Value>>,
    pub allow: Option<Allow>,
    pub webhook_ingress: Option<WebhookIngress>,
    pub burn_in: Option<BurnIn>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct Allow {
    pub ingress: Option<Vec<AllowRule>>,
    pub egress: Option<Vec<AllowRule>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct AllowRule {
    #[schemars(length(min = 1))]
    pub name: String,
    pub namespace: Option<String>,
    pub pod_labels: Option<BTreeMap<String, String>>,
    pub cidr: Option<String>,
    pub except: Option<Vec<String>>,
    pub ports: Option<Vec<Value>>,
    pub all_ports: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct WebhookIngress {
    pub cidr: Option<String>,
    pub ports: Option<Vec<Value>>,
    pub port: Option<Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct BurnIn {
    pub enabled: Option<bool>,
    pub until: Option<String>,
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct Access {
    pub effects: Option<Vec<Effect>>,
    pub egress: Option<Vec<Peer>>,
    pub reads: Option<Vec<Read>>,
    pub writes: Option<Vec<Write>>,
    pub listen: Option<Vec<ListenPort>>,
    pub exec: Option<Vec<String>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum Effect {
    Network,
    Filesystem,
    Clock,
    Entropy,
    Environment,
    Process,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct ListenPort(#[schemars(range(min = 1))] pub u16);

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum RuntimeKind {
    Native,
    Wasm,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum NativeReason {
    #[serde(rename = "")]
    None,
    #[serde(rename = "process")]
    Process,
    #[serde(rename = "host_program")]
    HostProgram,
    #[serde(rename = "device")]
    Device,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct Runtime {
    pub kind: Option<RuntimeKind>,
    #[schemars(regex(pattern = "^[a-z0-9]([-a-z0-9.]{0,251}[a-z0-9])?$"))]
    pub class: Option<String>,
    pub reason: Option<NativeReason>,
    pub component: Option<Component>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct Component {
    #[schemars(regex(pattern = "^$|^/nix/store/[^/]"))]
    pub closure: Option<String>,
    #[schemars(regex(pattern = "^$|^[^/]"))]
    pub path: Option<String>,
    #[schemars(regex(pattern = "^$|^[^/]"))]
    pub app: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(untagged)]
pub enum Peer {
    HostPort(HostPort),
    Binding(Binding),
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct HostPort(#[schemars(regex(pattern = "^[A-Za-z0-9.-]+:[0-9]{1,5}$"))] pub String);

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Binding {
    #[schemars(length(min = 1))]
    pub binding: String,
    pub host: Option<String>,
    #[schemars(range(min = 1))]
    pub port: u16,
    pub protocol: Option<Protocol>,
    pub namespace: Option<String>,
    pub pod_labels: Option<BTreeMap<String, String>>,
    pub cidr: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum Protocol {
    #[serde(rename = "TCP")]
    Tcp,
    #[serde(rename = "UDP")]
    Udp,
    #[serde(rename = "SCTP")]
    Sctp,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Read {
    #[schemars(regex(pattern = "^/"))]
    pub path: String,
    pub secret: Option<String>,
    pub config_map: Option<String>,
    pub projected: Option<Open>,
    pub items: Option<Vec<Value>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(untagged)]
pub enum Write {
    Path(MountPath),
    Volume(WriteVolume),
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct MountPath(#[schemars(regex(pattern = "^/"))] pub String);

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct WriteVolume {
    #[schemars(regex(pattern = "^/"))]
    pub path: String,
    pub claim_name: Option<String>,
    pub size_limit: Option<String>,
    pub medium: Option<Medium>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum Medium {
    Memory,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum StoreKind {
    ClusterSecretStore,
    SecretStore,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct SecretRef {
    #[schemars(regex(pattern = "^[a-z0-9]([-a-z0-9]{0,44}[a-z0-9])?$"))]
    pub name: String,
    #[schemars(length(min = 1))]
    pub store: String,
    pub store_kind: Option<StoreKind>,
    #[schemars(length(min = 1))]
    pub key: String,
    pub property: Option<String>,
    #[schemars(regex(pattern = "^[-._a-zA-Z0-9]+$"))]
    pub file: Option<String>,
    #[schemars(regex(pattern = "^/"))]
    pub path: String,
    pub refresh_interval: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Kenshi {
    pub enabled: Option<bool>,
    #[schemars(regex(pattern = "^[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$"))]
    pub service: Option<String>,
    #[schemars(regex(pattern = "^[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$"))]
    pub product: Option<String>,
    #[schemars(regex(pattern = "^[A-Za-z0-9]([-A-Za-z0-9_.]{0,61}[A-Za-z0-9])?$"))]
    pub environment: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Telemetry {
    pub logs: Option<Signal>,
    pub traces: Option<Signal>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Signal {
    pub enabled: Option<bool>,
    #[schemars(regex(pattern = "^https?://[^ ]+$"))]
    pub endpoint: Option<String>,
    pub service_name: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Placement {
    #[schemars(length(min = 1))]
    pub cluster: String,
    #[schemars(length(min = 1))]
    pub namespace: String,
    pub name: Option<String>,
    pub chart: ChartRef,
    pub values: Option<Open>,
    #[schemars(length(min = 1))]
    pub path: String,
    pub source_ref: SourceRef,
    pub create_namespace: Option<bool>,
    pub interval: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ChartRef {
    #[schemars(length(min = 1))]
    pub name: String,
    #[schemars(length(min = 1))]
    pub version: String,
    pub source_ref: SourceRef,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub struct SourceRef {
    pub kind: Option<String>,
    #[schemars(length(min = 1))]
    pub name: String,
    pub namespace: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ExternalSecret {
    pub api_version: Option<String>,
    pub cluster_secret_store_name: Option<String>,
    pub refresh_interval: Option<String>,
    pub secrets: Option<Open>,
}

fn splice_rules(schema: &mut Value) {
    let Some(read) = schema
        .get_mut("definitions")
        .and_then(|d| d.get_mut("Read"))
        .and_then(Value::as_object_mut)
    else {
        return;
    };
    read.insert(
        "oneOf".into(),
        json!([
            { "required": ["secret"] },
            { "required": ["configMap"] },
            { "required": ["projected"] }
        ]),
    );
}

#[must_use]
pub fn schema() -> Value {
    let mut value = strict_schema_value::<PlemeLibValues>();
    splice_rules(&mut value);
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_top_level_is_closed() {
        assert_eq!(schema()["additionalProperties"], Value::Bool(false));
    }

    #[test]
    fn nothing_at_the_top_is_required() {
        assert!(schema().get("required").is_none());
    }

    #[test]
    fn helm_global_is_admitted() {
        assert!(schema()["properties"]["global"].is_object());
    }

    #[test]
    fn a_read_takes_exactly_one_source() {
        let v = schema();
        assert_eq!(v["definitions"]["Read"]["oneOf"].as_array().unwrap().len(), 3);
        assert_eq!(v["definitions"]["Read"]["additionalProperties"], Value::Bool(false));
    }

    #[test]
    fn a_secret_ref_has_no_literal_field() {
        let v = schema();
        let props = v["definitions"]["SecretRef"]["properties"].as_object().unwrap();
        for literal in ["value", "data", "stringData", "literal"] {
            assert!(!props.contains_key(literal));
        }
        assert_eq!(v["definitions"]["SecretRef"]["additionalProperties"], Value::Bool(false));
    }

    #[test]
    fn telemetry_endpoints_are_urls_and_each_signal_closes() {
        let v = schema();
        assert_eq!(
            v["definitions"]["Signal"]["properties"]["endpoint"]["pattern"],
            Value::String("^https?://[^ ]+$".into())
        );
        assert_eq!(v["definitions"]["Signal"]["additionalProperties"], Value::Bool(false));
        assert_eq!(v["definitions"]["Kenshi"]["additionalProperties"], Value::Bool(false));
    }

    #[test]
    fn the_runtime_names_two_kinds_and_three_native_reasons() {
        let v = schema();
        assert_eq!(v["definitions"]["Runtime"]["additionalProperties"], Value::Bool(false));
        assert_eq!(v["definitions"]["Component"]["additionalProperties"], Value::Bool(false));
        assert_eq!(v["definitions"]["RuntimeKind"]["enum"], json!(["native", "wasm"]));
        assert_eq!(
            v["definitions"]["NativeReason"]["enum"],
            json!(["", "process", "host_program", "device"])
        );
    }

    #[test]
    fn access_names_the_six_effects() {
        let v = schema();
        assert_eq!(
            v["definitions"]["Effect"]["enum"],
            json!(["network", "filesystem", "clock", "entropy", "environment", "process"])
        );
    }

    #[test]
    fn a_placement_pins_its_chart_version() {
        let v = schema();
        let required = v["definitions"]["ChartRef"]["required"].as_array().unwrap();
        assert!(required.iter().any(|r| r == "version"));
    }
}
