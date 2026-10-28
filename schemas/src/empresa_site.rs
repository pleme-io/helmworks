use helm_forge::values_schema::strict_schema_value;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::BTreeMap;


#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct EmpresaSiteValues {
    #[schemars(regex(pattern = "^[a-z0-9]([a-z0-9-]{0,28}[a-z0-9])?$"), length(min = 1, max = 30))]
    pub company: String,
    #[schemars(length(min = 1))]
    pub hosts: Vec<Hostname>,
    #[serde(default = "default_path_prefix")]
    #[schemars(regex(pattern = "^(/|(/[a-z0-9][a-z0-9._~-]*)+)$"))]
    pub path_prefix: String,
    #[serde(default)]
    pub content: Content,
    #[serde(default)]
    pub server: Server,
    #[serde(default)]
    pub service: Service,
    #[serde(default)]
    pub resources: Resources,
    #[serde(default)]
    pub node_selector: BTreeMap<String, String>,
    #[serde(default = "default_replicas")]
    #[schemars(range(min = 1, max = 10))]
    pub replica_count: u8,
    #[serde(default)]
    pub image_pull_secrets: Vec<PullSecret>,
    #[serde(default)]
    #[schemars(regex(pattern = "^$|^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"))]
    pub name_override: String,
    #[serde(default)]
    #[schemars(regex(pattern = "^$|^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"))]
    pub fullname_override: String,
    #[serde(default, rename = "pleme-lib")]
    pub pleme_lib: BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(transparent)]
pub struct Hostname(#[schemars(regex(pattern = "^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$"), length(max = 253))] pub String);

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Content {
    #[serde(default)]
    pub image: Image,
    #[serde(default)]
    pub placeholder: Placeholder,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Placeholder {
    #[serde(default = "default_true")]
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Server {
    #[serde(default = "default_server_image")]
    pub image: Image,
    #[serde(default)]
    pub pull_policy: PullPolicy,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct Image {
    #[schemars(schema_with = "crate::oci::repository")]
    pub repository: String,
    #[serde(default)]
    #[schemars(schema_with = "crate::oci::tag")]
    pub tag: String,
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
pub struct Service {
    #[serde(default = "default_port")]
    #[schemars(range(min = 1024, max = 65534))]
    pub port: u16,
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
    #[schemars(regex(pattern = "^[0-9]+(\\.[0-9]+)?(m|k|M|G|Ki|Mi|Gi)?$"))]
    pub cpu: String,
    #[schemars(regex(pattern = "^[0-9]+(\\.[0-9]+)?(m|k|M|G|Ki|Mi|Gi)?$"))]
    pub memory: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
pub struct PullSecret {
    #[schemars(length(min = 1))]
    pub name: String,
}

fn default_path_prefix() -> String {
    "/".into()
}
fn default_replicas() -> u8 {
    1
}
fn default_true() -> bool {
    true
}
fn default_port() -> u16 {
    8080
}
fn default_server_image() -> Image {
    Image {
        repository: "ghcr.io/pleme-io/hanabi".into(),
        tag: String::new(),
    }
}

impl Default for Content {
    fn default() -> Self {
        Self {
            image: Image::default(),
            placeholder: Placeholder::default(),
        }
    }
}
impl Default for Placeholder {
    fn default() -> Self {
        Self { enabled: true }
    }
}
impl Default for Server {
    fn default() -> Self {
        Self {
            image: default_server_image(),
            pull_policy: PullPolicy::default(),
        }
    }
}
impl Default for Service {
    fn default() -> Self {
        Self { port: default_port() }
    }
}
impl Default for Resources {
    fn default() -> Self {
        Self {
            requests: Quantities {
                cpu: "10m".into(),
                memory: "16Mi".into(),
            },
            limits: Quantities {
                cpu: "200m".into(),
                memory: "64Mi".into(),
            },
        }
    }
}

fn not_latest() -> Value {
    json!({ "not": { "const": "latest" } })
}

fn splice_rules(schema: &mut Value) {
    let Some(defs) = schema.get_mut("definitions").and_then(Value::as_object_mut) else {
        return;
    };
    if let Some(Value::Object(props)) = defs.get_mut("Image").and_then(|d| d.get_mut("properties")) {
        if let Some(Value::Object(tag)) = props.get_mut("tag") {
            tag.insert("not".into(), not_latest()["not"].clone());
        }
    }
    let Some(root) = schema.as_object_mut() else {
        return;
    };
    root.entry("allOf").or_insert_with(|| json!([])).as_array_mut().map(|rules| {
        rules.push(json!({
            "if": {
                "properties": {
                    "content": {
                        "properties": { "placeholder": { "properties": { "enabled": { "const": false } }, "required": ["enabled"] } },
                        "required": ["placeholder"]
                    }
                },
                "required": ["content"]
            },
            "then": {
                "properties": {
                    "content": {
                        "properties": {
                            "image": {
                                "properties": {
                                    "repository": { "minLength": 1 },
                                    "tag": { "minLength": 1 }
                                },
                                "required": ["repository", "tag"]
                            }
                        },
                        "required": ["image"]
                    }
                }
            }
        }));
    });
}

#[must_use]
pub fn schema() -> Value {
    let mut value = strict_schema_value::<EmpresaSiteValues>();
    splice_rules(&mut value);
    value
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn company_and_hosts_are_required() {
        let v = schema();
        let required = v["required"].as_array().unwrap();
        assert!(required.iter().any(|r| r == "company"));
        assert!(required.iter().any(|r| r == "hosts"));
    }

    #[test]
    fn every_owned_object_is_closed() {
        let v = schema();
        assert_eq!(v["additionalProperties"], Value::Bool(false));
        assert_eq!(v["definitions"]["Content"]["additionalProperties"], Value::Bool(false));
        assert_eq!(v["definitions"]["Image"]["additionalProperties"], Value::Bool(false));
        assert_eq!(v["definitions"]["Resources"]["additionalProperties"], Value::Bool(false));
    }

    #[test]
    fn node_selector_stays_an_open_string_map() {
        let v = schema();
        assert_eq!(v["properties"]["nodeSelector"]["additionalProperties"]["type"], "string");
    }

    #[test]
    fn placeholder_off_demands_a_content_image() {
        let v = schema();
        let rule = &v["allOf"][0];
        assert_eq!(
            rule["then"]["properties"]["content"]["properties"]["image"]["required"],
            json!(["repository", "tag"])
        );
    }

    #[test]
    fn latest_tag_is_refused() {
        let v = schema();
        assert_eq!(v["definitions"]["Image"]["properties"]["tag"]["not"]["const"], "latest");
    }
}
