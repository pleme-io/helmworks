use helm_forge::values_schema::{emit, render, Mode, Outcome};
use helmworks_values_schema::CHARTS;
use std::path::PathBuf;
use std::process::ExitCode;

fn charts_dir(args: &[String]) -> PathBuf {
    args.windows(2)
        .find(|w| w[0] == "--charts")
        .map_or_else(|| PathBuf::from("charts"), |w| PathBuf::from(&w[1]))
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().collect();
    let mode = Mode::from_args(&args);
    let dir = charts_dir(&args);
    let mut stale = false;
    for entry in CHARTS {
        let path = dir.join(entry.chart).join("values.schema.json");
        let rendered = render(&(entry.generate)());
        match emit(&path, &rendered, mode) {
            Ok(Outcome::Fresh) => println!("fresh    {}", path.display()),
            Ok(Outcome::Written) => println!("written  {}", path.display()),
            Ok(Outcome::Stale) => {
                stale = true;
                eprintln!(
                    "stale    {}: run `cargo run --manifest-path schemas/Cargo.toml` and commit",
                    path.display()
                );
            }
            Err(e) => {
                eprintln!("error    {}: {e}", path.display());
                return ExitCode::from(2);
            }
        }
    }
    if stale {
        ExitCode::from(1)
    } else {
        ExitCode::SUCCESS
    }
}
