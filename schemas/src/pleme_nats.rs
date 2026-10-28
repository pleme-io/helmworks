use helm_forge::values_schema::strict_schema_value;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PlemeNatsValues {
    pub enabled: bool,
    pub runtime: Runtime,
    pub native: Native,
    pub image: Image,
    pub exporter: Exporter,
    #[serde(default)]
    pub image_pull_secrets: Vec<Value>,
    #[serde(default)]
    pub name_override: String,
    #[serde(default)]
    pub fullname_override: String,
    #[schemars(range(min = 1, max = 1))]
    pub replica_count: u8,
    pub service_account: ServiceAccount,
    pub server: Server,
    pub persistence: Persistence,
    pub resources: Resources,
    #[serde(default)]
    pub extra_env: Vec<Value>,
    pub termination_grace_period_seconds: u32,
    #[serde(default)]
    pub pod_security_context: BTreeMap<String, Value>,
    #[serde(default)]
    pub security_context: BTreeMap<String, Value>,
    pub service: Service,
    pub service_monitor: ServiceMonitor,
    pub vm_scrape: VmScrape,
    pub network_policy: NetworkPolicy,
    pub pdb: Pdb,
    pub prometheus_rules: PrometheusRules,
    #[serde(default)]
    pub compliance: BTreeMap<String, Value>,
    #[serde(default)]
    pub monitoring: BTreeMap<String, Value>,
    #[serde(default)]
    pub node_selector: BTreeMap<String, String>,
    #[serde(default)]
    pub tolerations: Vec<Value>,
    #[serde(default)]
    pub affinity: BTreeMap<String, Value>,
    #[serde(default)]
    pub additional_labels: BTreeMap<String, String>,
    #[serde(default)]
    pub annotations: BTreeMap<String, String>,
    #[serde(default)]
    pub attestation: BTreeMap<String, Value>,
    #[serde(default, rename = "pleme-lib")]
    pub pleme_lib: BTreeMap<String, Value>,
    #[serde(default)]
    pub global: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum Runtime {
    Oci,
    Native,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Native {
    #[schemars(
        description = "file: nats-server -c reads the chart's nats.conf from the ConfigMap where engenho materializes it (every server value applies). flags: the server runs on flags alone and the file store, memory store, payload, pending and connection limits are not applied."
    )]
    pub config: NativeConfig,
    #[schemars(
        description = "The node's engenho volume area, <engenho dataDir>/volumes. engenho writes a ConfigMap volume to <volumeRoot>/<namespace>_<pod>/<volume>, and a native process reads it at that path."
    )]
    pub volume_root: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum NativeConfig {
    File,
    Flags,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Image {
    #[schemars(length(min = 1))]
    pub repository: String,
    #[schemars(length(min = 1))]
    pub tag: String,
    pub pull_policy: PullPolicy,
    #[serde(default)]
    pub digest: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum PullPolicy {
    Always,
    IfNotPresent,
    Never,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Exporter {
    pub enabled: bool,
    pub image: ExporterImage,
    pub resources: Resources,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ExporterImage {
    pub repository: String,
    pub tag: String,
    pub pull_policy: PullPolicy,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ServiceAccount {
    pub create: bool,
    #[serde(default)]
    pub annotations: BTreeMap<String, String>,
    #[serde(default)]
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Server {
    #[schemars(length(min = 1))]
    pub host: String,
    #[schemars(range(min = 1, max = 65535))]
    pub port: u16,
    #[schemars(range(min = 1, max = 65535))]
    pub monitoring_port: u16,
    pub cluster_enabled: bool,
    #[schemars(regex(pattern = "^[0-9]+(ms|s|m|h)$"))]
    pub ping_interval: String,
    #[schemars(regex(pattern = "^[0-9]+(ms|s|m|h)$"))]
    pub write_deadline: String,
    #[schemars(range(min = 1))]
    pub max_connections: u32,
    #[schemars(regex(pattern = "^[0-9]+(B|KB|MB|GB|TB|K|M|G|T)?$"))]
    pub max_payload: String,
    #[schemars(regex(pattern = "^[0-9]+(B|KB|MB|GB|TB|K|M|G|T)?$"))]
    pub max_pending: String,
    pub auth: Auth,
    pub jetstream: JetStream,
    #[serde(default)]
    pub extra_config: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Auth {
    pub enabled: bool,
    #[schemars(
        description = "secret: user and password from secretName, an authorization block on $NATS_USER and $NATS_PASSWORD. file: nats.conf includes the authorization fragment at the absolute host path file (runtime native, native.config file)."
    )]
    pub source: AuthSource,
    pub secret_name: String,
    #[schemars(length(min = 1))]
    pub user_key: String,
    #[schemars(length(min = 1))]
    pub password_key: String,
    pub file: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum AuthSource {
    Secret,
    File,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct JetStream {
    pub enabled: bool,
    #[schemars(length(min = 1))]
    pub store_dir: String,
    #[schemars(regex(pattern = "^[0-9]+(B|KB|MB|GB|TB|K|M|G|T)?$"))]
    pub max_memory_store: String,
    #[schemars(regex(pattern = "^[0-9]+(B|KB|MB|GB|TB|K|M|G|T)?$"))]
    pub max_file_store: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Persistence {
    pub enabled: bool,
    #[serde(default)]
    pub storage_class: String,
    #[schemars(regex(pattern = "^[0-9]+(\\.[0-9]+)?(k|M|G|T|Ki|Mi|Gi|Ti)$"))]
    pub size: String,
    pub access_mode: AccessMode,
    #[schemars(length(min = 1))]
    pub mount_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum AccessMode {
    ReadWriteOnce,
    ReadWriteOncePod,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Resources {
    #[serde(default)]
    pub requests: BTreeMap<String, Value>,
    #[serde(default)]
    pub limits: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Service {
    pub r#type: ServiceType,
    #[serde(rename = "clusterIP")]
    pub cluster_ip: String,
    pub ports: ServicePorts,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
pub enum ServiceType {
    ClusterIP,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ServicePorts {
    #[schemars(range(min = 1, max = 65535))]
    pub client: u16,
    #[schemars(range(min = 1, max = 65535))]
    pub monitoring: u16,
    #[schemars(range(min = 1, max = 65535))]
    pub metrics: u16,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ServiceMonitor {
    pub enabled: bool,
    pub interval: String,
    pub scrape_timeout: String,
    pub port: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct VmScrape {
    pub enabled: bool,
    pub port: String,
    pub path: String,
    pub interval: String,
    pub scrape_timeout: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct NetworkPolicy {
    pub enabled: bool,
    pub allow_dns: bool,
    pub allow_prometheus: bool,
    #[serde(default)]
    pub prometheus_namespaces: Vec<String>,
    #[serde(default)]
    pub allowed_client_namespaces: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Pdb {
    pub enabled: bool,
    pub min_available: u32,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PrometheusRules {
    pub enabled: bool,
    #[serde(default)]
    pub groups: Vec<Value>,
}

fn when(conditions: Value, then: Value) -> Value {
    json!({ "if": conditions, "then": then })
}

fn native_file() -> Value {
    json!({
        "properties": {
            "runtime": { "const": "native" },
            "native": { "properties": { "config": { "const": "file" } }, "required": ["config"] }
        },
        "required": ["runtime", "native"]
    })
}

fn auth_with(source: &str) -> Value {
    json!({
        "properties": { "server": {
            "properties": { "auth": {
                "properties": { "enabled": { "const": true }, "source": { "const": source } },
                "required": ["enabled", "source"]
            } },
            "required": ["auth"]
        } },
        "required": ["server"]
    })
}

fn splice_rules(schema: &mut Value) {
    let Some(root) = schema.as_object_mut() else {
        return;
    };
    let rules = root.entry("allOf").or_insert_with(|| json!([]));
    let Some(rules) = rules.as_array_mut() else {
        return;
    };
    rules.push(when(
        native_file(),
        json!({ "properties": { "native": { "properties": { "volumeRoot": { "pattern": "^/" } } } } }),
    ));
    rules.push(when(
        auth_with("secret"),
        json!({ "properties": { "server": { "properties": { "auth": {
            "properties": { "secretName": { "minLength": 1 } }
        } } } } }),
    ));
    rules.push(when(
        auth_with("file"),
        json!({
            "allOf": [native_file()],
            "properties": { "server": { "properties": { "auth": {
                "properties": { "file": { "pattern": "^/" } }
            } } } }
        }),
    ));
}

#[must_use]
pub fn schema() -> Value {
    let mut value = strict_schema_value::<PlemeNatsValues>();
    splice_rules(&mut value);
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    const SIZE: &str = "^[0-9]+(B|KB|MB|GB|TB|K|M|G|T)?$";
    const DURATION: &str = "^[0-9]+(ms|s|m|h)$";

    #[test]
    fn owned_objects_are_closed() {
        let v = schema();
        assert_eq!(v["additionalProperties"], Value::Bool(false));
        for name in ["Server", "Auth", "JetStream", "Native"] {
            assert_eq!(v["definitions"][name]["additionalProperties"], Value::Bool(false), "{name}");
        }
    }

    #[test]
    fn the_runtime_native_config_and_auth_source_are_closed_enums() {
        let v = schema();
        assert_eq!(v["definitions"]["Runtime"]["enum"], json!(["oci", "native"]));
        assert_eq!(v["definitions"]["NativeConfig"]["enum"], json!(["file", "flags"]));
        assert_eq!(v["definitions"]["AuthSource"]["enum"], json!(["secret", "file"]));
    }

    #[test]
    fn the_jetstream_limits_are_typed_sizes() {
        let v = schema();
        let js = &v["definitions"]["JetStream"]["properties"];
        assert_eq!(js["maxFileStore"]["pattern"], SIZE);
        assert_eq!(js["maxMemoryStore"]["pattern"], SIZE);
        assert_eq!(v["definitions"]["Server"]["properties"]["maxPayload"]["pattern"], SIZE);
        assert_eq!(v["definitions"]["Server"]["properties"]["pingInterval"]["pattern"], DURATION);
    }

    #[test]
    fn native_file_config_demands_an_absolute_volume_root() {
        let v = schema();
        let rule = &v["allOf"][0];
        assert_eq!(rule["if"]["properties"]["native"]["properties"]["config"]["const"], "file");
        assert_eq!(rule["then"]["properties"]["native"]["properties"]["volumeRoot"]["pattern"], "^/");
    }

    #[test]
    fn auth_from_a_file_demands_native_file_config_and_an_absolute_path() {
        let v = schema();
        let rule = &v["allOf"][2];
        assert_eq!(rule["if"]["properties"]["server"]["properties"]["auth"]["properties"]["source"]["const"], "file");
        assert_eq!(rule["then"]["allOf"][0]["properties"]["runtime"]["const"], "native");
        assert_eq!(rule["then"]["properties"]["server"]["properties"]["auth"]["properties"]["file"]["pattern"], "^/");
    }
}
