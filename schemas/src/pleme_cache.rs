use helm_forge::values_schema::strict_schema_value;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PlemeCacheValues {
    #[serde(default = "yes")]
    pub enabled: bool,
    pub image: Image,
    #[serde(default)]
    pub image_pull_secrets: Vec<PullSecret>,
    #[serde(default)]
    #[schemars(regex(pattern = "^$|^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"))]
    pub name_override: String,
    #[serde(default)]
    #[schemars(regex(pattern = "^$|^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"))]
    pub fullname_override: String,
    #[serde(default = "one")]
    #[schemars(range(min = 1, max = 1))]
    pub replica_count: u8,
    #[serde(default)]
    pub service_account: ServiceAccount,
    #[serde(default)]
    pub service: Service,
    pub cache: Cache,
    pub exporter: Exporter,
    #[serde(default)]
    pub service_monitor: ServiceMonitor,
    #[serde(default)]
    pub monitoring: Monitoring,
    pub resources: Resources,
    #[serde(default)]
    pub network_policy: NetworkPolicy,
    #[serde(default)]
    pub command: Vec<String>,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub env: Vec<Value>,
    #[serde(default)]
    pub volume_mounts: Vec<Value>,
    #[serde(default)]
    pub volumes: Vec<Value>,
    #[serde(default)]
    pub health: Health,
    #[serde(default)]
    pub termination_grace_period_seconds: u32,
    #[serde(default)]
    pub pod_annotations: BTreeMap<String, String>,
    #[serde(default)]
    pub node_selector: BTreeMap<String, String>,
    #[serde(default)]
    pub tolerations: Vec<Value>,
    #[serde(default)]
    pub affinity: BTreeMap<String, Value>,
    #[serde(default)]
    pub priority_class_name: String,
    #[serde(default)]
    pub additional_labels: BTreeMap<String, String>,
    #[serde(default)]
    pub ports: Vec<Value>,
    #[serde(default)]
    pub startup_probe: BTreeMap<String, Value>,
    #[serde(default)]
    pub pod_security_context: BTreeMap<String, Value>,
    #[serde(default)]
    pub security_context: BTreeMap<String, Value>,
    #[serde(default)]
    pub config_maps: Vec<Value>,
    #[serde(default)]
    pub downward_api: BTreeMap<String, Value>,
    #[serde(default)]
    pub istio: BTreeMap<String, Value>,
    #[serde(default)]
    pub pod_monitor: BTreeMap<String, Value>,
    #[serde(default)]
    pub prometheus_rules: BTreeMap<String, Value>,
    #[serde(default, rename = "pleme-lib")]
    pub pleme_lib: BTreeMap<String, Value>,
    #[serde(default)]
    pub global: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Image {
    #[schemars(regex(pattern = "^$|^[a-z0-9]([a-z0-9._-]*[a-z0-9])?(:[0-9]+)?(/[a-z0-9]([a-z0-9._-]*[a-z0-9])?)+$"))]
    pub repository: String,
    #[schemars(regex(pattern = "^$|^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$"))]
    pub tag: String,
    #[serde(default)]
    pub pull_policy: PullPolicy,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
pub enum PullPolicy {
    Always,
    #[default]
    IfNotPresent,
    Never,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PullSecret {
    #[schemars(length(min = 1))]
    pub name: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ServiceAccount {
    #[serde(default)]
    pub create: bool,
    #[serde(default)]
    pub annotations: BTreeMap<String, String>,
    #[serde(default)]
    pub name: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
pub struct Service {
    #[serde(default)]
    pub r#type: ServiceType,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
pub enum ServiceType {
    #[default]
    ClusterIP,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Cache {
    #[schemars(range(min = 1024, max = 65535))]
    pub port: u16,
    #[schemars(regex(pattern = "^[0-9]+(b|kb|mb|gb|k|m|g)?$"))]
    pub maxmemory: String,
    pub maxmemory_policy: EvictionPolicy,
    #[serde(rename = "password")]
    pub auth: Password,
    pub tls: Tls,
    pub persistence: Persistence,
    #[serde(default)]
    pub extra_config: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "kebab-case")]
pub enum EvictionPolicy {
    Noeviction,
    AllkeysLru,
    AllkeysLfu,
    AllkeysRandom,
    VolatileLru,
    VolatileLfu,
    VolatileRandom,
    VolatileTtl,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Password {
    pub enabled: bool,
    pub secret_name: String,
    #[schemars(length(min = 1))]
    pub key: String,
    pub delivery: Delivery,
    pub include_key: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum Delivery {
    Include,
    Init,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Tls {
    pub enabled: bool,
    pub secret_name: String,
    pub client_auth: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Persistence {
    pub enabled: bool,
    #[schemars(regex(pattern = "^[0-9]+(\\.[0-9]+)?(k|M|G|Ki|Mi|Gi|Ti)$"))]
    pub size: String,
    pub appendfsync: Appendfsync,
    #[serde(default)]
    pub storage_class: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum Appendfsync {
    Always,
    Everysec,
    No,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Exporter {
    pub enabled: bool,
    pub image: ExporterImage,
    #[schemars(range(min = 1024, max = 65535))]
    pub port: u16,
    pub resources: Resources,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ExporterImage {
    pub repository: String,
    pub tag: String,
    pub pull_policy: PullPolicy,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct ServiceMonitor {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub interval: String,
    #[serde(default)]
    pub scrape_timeout: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Monitoring {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub port: String,
    #[serde(default)]
    pub path: String,
    #[serde(default)]
    pub interval: String,
    #[serde(default)]
    pub scrape_timeout: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Resources {
    pub requests: Quantities,
    pub limits: Quantities,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Quantities {
    #[schemars(regex(pattern = "^[0-9]+(\\.[0-9]+)?m?$"))]
    pub cpu: String,
    #[schemars(regex(pattern = "^[0-9]+(\\.[0-9]+)?(k|M|G|Ki|Mi|Gi)?$"))]
    pub memory: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct NetworkPolicy {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub allow_prometheus: bool,
    #[serde(default)]
    pub allow_dns: bool,
    #[serde(default)]
    pub additional_ingress: Vec<Value>,
    #[serde(default)]
    pub additional_egress: Vec<Value>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Health {
    #[serde(default)]
    pub liveness_initial_delay: u32,
    #[serde(default)]
    pub liveness_period: u32,
    #[serde(default)]
    pub liveness_failure_threshold: u32,
    #[serde(default)]
    pub readiness_initial_delay: u32,
    #[serde(default)]
    pub readiness_period: u32,
    #[serde(default)]
    pub readiness_failure_threshold: u32,
}

fn yes() -> bool {
    true
}
fn one() -> u8 {
    1
}

fn not_latest() -> Value {
    json!({ "not": { "const": "latest" } })
}

fn when(property: &str, path: &[&str], then: Value) -> Value {
    let mut condition = json!({ "properties": { property: { "const": true } }, "required": [property] });
    for key in path.iter().rev() {
        condition = json!({ "properties": { *key: condition }, "required": [*key] });
    }
    json!({ "if": condition, "then": then })
}

fn splice_rules(schema: &mut Value) {
    let Some(defs) = schema.get_mut("definitions").and_then(Value::as_object_mut) else {
        return;
    };
    for name in ["Image", "ExporterImage"] {
        if let Some(Value::Object(props)) = defs.get_mut(name).and_then(|d| d.get_mut("properties")) {
            if let Some(Value::Object(tag)) = props.get_mut("tag") {
                tag.insert("not".into(), not_latest()["not"].clone());
            }
        }
    }
    let Some(root) = schema.as_object_mut() else {
        return;
    };
    let rules = root.entry("allOf").or_insert_with(|| json!([]));
    let Some(rules) = rules.as_array_mut() else {
        return;
    };
    rules.push(json!({
        "if": { "properties": { "enabled": { "const": true } } },
        "then": { "properties": { "image": {
            "properties": { "repository": { "minLength": 1 }, "tag": { "minLength": 1 } },
            "required": ["repository", "tag"]
        } } }
    }));
    rules.push(when(
        "enabled",
        &["cache", "password"],
        json!({ "properties": { "cache": { "properties": { "password": {
            "properties": { "secretName": { "minLength": 1 } },
            "required": ["secretName"]
        } } } } }),
    ));
    rules.push(when(
        "enabled",
        &["cache", "tls"],
        json!({ "properties": { "cache": { "properties": { "tls": {
            "properties": { "secretName": { "minLength": 1 } },
            "required": ["secretName"]
        } } } } }),
    ));
}

#[must_use]
pub fn schema() -> Value {
    let mut value = strict_schema_value::<PlemeCacheValues>();
    splice_rules(&mut value);
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn image_is_required_and_never_latest() {
        let v = schema();
        assert!(v["required"].as_array().unwrap().iter().any(|r| r == "image"));
        assert_eq!(v["definitions"]["Image"]["properties"]["tag"]["not"]["const"], "latest");
        assert_eq!(v["definitions"]["ExporterImage"]["properties"]["tag"]["not"]["const"], "latest");
    }

    #[test]
    fn a_password_has_no_literal_field() {
        let v = schema();
        let props = v["definitions"]["Password"]["properties"].as_object().unwrap();
        let literal = ["val", "ue"].concat();
        assert!(!props.contains_key(&literal));
        assert!(props.contains_key("secretName"));
    }

    #[test]
    fn password_on_demands_a_secret_name() {
        let v = schema();
        let rule = &v["allOf"][1];
        assert_eq!(
            rule["then"]["properties"]["cache"]["properties"]["password"]["required"],
            json!(["secretName"])
        );
    }

    #[test]
    fn tls_on_demands_a_secret_name() {
        let v = schema();
        let rule = &v["allOf"][2];
        assert_eq!(
            rule["then"]["properties"]["cache"]["properties"]["tls"]["required"],
            json!(["secretName"])
        );
    }

    #[test]
    fn service_is_cluster_ip_only() {
        let v = schema();
        assert_eq!(v["definitions"]["ServiceType"]["enum"], json!(["ClusterIP"]));
    }

    #[test]
    fn owned_objects_are_closed() {
        let v = schema();
        assert_eq!(v["additionalProperties"], Value::Bool(false));
        assert_eq!(v["definitions"]["Cache"]["additionalProperties"], Value::Bool(false));
        assert_eq!(v["definitions"]["Password"]["additionalProperties"], Value::Bool(false));
    }
}
