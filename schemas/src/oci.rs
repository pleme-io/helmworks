use schemars::gen::SchemaGenerator;
use schemars::schema::{InstanceType, Schema, SchemaObject, StringValidation};

pub const REPOSITORY: &str = "^$|^[a-z0-9]([a-z0-9._-]*[a-z0-9])?(:[0-9]+)?(/[a-z0-9]([a-z0-9._-]*[a-z0-9])?)*(@sha256:[a-f0-9]{64})?$";

pub const TAG: &str = "^$|^[A-Za-z0-9_][A-Za-z0-9._-]{0,127}$|^sha256:[a-f0-9]{64}$";

fn patterned(pattern: &str) -> Schema {
    SchemaObject {
        instance_type: Some(InstanceType::String.into()),
        string: Some(Box::new(StringValidation {
            pattern: Some(pattern.to_string()),
            ..Default::default()
        })),
        ..Default::default()
    }
    .into()
}

pub fn repository(_: &mut SchemaGenerator) -> Schema {
    patterned(REPOSITORY)
}

pub fn tag(_: &mut SchemaGenerator) -> Schema {
    patterned(TAG)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn matches(pattern: &str, value: &str) -> bool {
        regex::Regex::new(pattern).unwrap().is_match(value)
    }

    #[test]
    fn a_repository_follows_the_oci_reference_grammar() {
        for ok in [
            "",
            "test",
            "redis",
            "ghcr.io/pleme-io/hardened-valkey",
            "localhost:5000/a/b",
            "ghcr.io/x/y@sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ] {
            assert!(matches(REPOSITORY, ok), "{ok} should be a repository");
        }
        for bad in ["Ghcr.io/x", "a//b", "/a", "a/", "a b"] {
            assert!(!matches(REPOSITORY, bad), "{bad} should be refused");
        }
    }

    #[test]
    fn a_tag_is_a_tag_or_the_digest_pleme_lib_renders_as_repo_at_digest() {
        for ok in [
            "",
            "v1.18.0",
            "8.0",
            "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        ] {
            assert!(matches(TAG, ok), "{ok} should be a tag");
        }
        for bad in [".x", "a:b", "sha256:abc", "-x"] {
            assert!(!matches(TAG, bad), "{bad} should be refused");
        }
    }
}
