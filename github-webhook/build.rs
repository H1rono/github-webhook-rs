use anyhow::Result;
use cargo_metadata::{CargoOpt, MetadataCommand};
use std::env;

use github_webhook_dts_downloader::run_transform;

fn main() -> Result<()> {
    println!("cargo:rerun-if-env-changed=WEBHOOK_SCHEMA_DTS");

    let manifest_dir = env!("CARGO_MANIFEST_DIR").to_string();
    let metadata = MetadataCommand::new()
        .manifest_path(manifest_dir + "/Cargo.toml")
        .features(CargoOpt::AllFeatures)
        .no_deps() // prevent generate lockfile
        .exec()
        .unwrap();

    // workspace manifest
    assert_ne!(metadata.workspace_members.len(), 0);

    let pkg_name = env!("CARGO_PKG_NAME");
    let pkg = &metadata
        .packages
        .iter()
        .find(|p| p.name == pkg_name)
        .unwrap();

    assert_eq!(pkg_name, pkg.name);

    let octokit_webhooks = pkg
        .metadata
        .get("octokit-webhooks")
        .expect("Could not get octokit-webhooks metadata");

    let octokit_ver = octokit_webhooks
        .get("version")
        .expect("Could not get octokit/webhooks version")
        .as_str()
        .unwrap()
        .to_string();

    let out_path_ts = env::var("WEBHOOK_SCHEMA_DTS")
        .ok()
        .map(|p| p.parse().unwrap())
        .map(github_webhook_dts_downloader::OutPathTs)
        .unwrap_or_default();
    let opt = github_webhook_dts_downloader::Opt {
        version: github_webhook_dts_downloader::Version(octokit_ver),
        out_path_ts,
        ..Default::default()
    };
    run_transform(opt)?;

    Ok(())
}
