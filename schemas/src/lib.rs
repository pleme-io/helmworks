pub mod empresa_site;

use serde_json::Value;

pub struct ChartSchema {
    pub chart: &'static str,
    pub generate: fn() -> Value,
}

pub const CHARTS: &[ChartSchema] = &[ChartSchema {
    chart: "empresa-site",
    generate: empresa_site::schema,
}];
