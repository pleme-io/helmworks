pub mod empresa_site;
pub mod pleme_cache;
pub mod pleme_lib;

use serde_json::Value;

pub struct ChartSchema {
    pub chart: &'static str,
    pub generate: fn() -> Value,
}

pub const CHARTS: &[ChartSchema] = &[ChartSchema {
    chart: "empresa-site",
    generate: empresa_site::schema,
},
ChartSchema {
    chart: "pleme-cache",
    generate: pleme_cache::schema,
},
ChartSchema {
    chart: "pleme-lib",
    generate: pleme_lib::schema,
}];
