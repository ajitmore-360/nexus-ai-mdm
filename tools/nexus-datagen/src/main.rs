mod generators;
mod output;
mod summary;

use anyhow::Result;
use clap::{Parser, ValueEnum};
use uuid::Uuid;

use generators::{add_duplicates, customer::CustomerGenerator, product::ProductGenerator, vendor::VendorGenerator, EntityGenerator};
use output::{post_to_api, write_csv, write_json};
use summary::print_summary;

// ─────────────────────────────────────────────────────────────────────────────
// CLI definition
// ─────────────────────────────────────────────────────────────────────────────

#[derive(Debug, Parser)]
#[command(
    name    = "nexus-datagen",
    about   = "Nexus AI MDM — Synthetic Entity Data Generator",
    version = "1.0.0",
    long_about = "Generates realistic enterprise entity data and loads it into Nexus AI MDM via the ingest API."
)]
struct Cli {
    /// Number of base entities to generate (duplicates are added on top)
    #[arg(short = 'n', long, default_value = "100")]
    count: usize,

    /// Entity type to generate
    #[arg(short, long, default_value = "customer")]
    r#type: EntityType,

    /// Target tenant ID
    #[arg(long, default_value = "00000000-0000-0000-0000-000000000001")]
    tenant_id: Uuid,

    /// Output format
    #[arg(short, long, default_value = "api")]
    output: OutputFormat,

    /// Ingest service / API gateway URL
    #[arg(long, default_value = "http://localhost:8080")]
    api_url: String,

    /// Bearer token for API authentication
    #[arg(long, default_value = "nexus-local-dev-token")]
    auth_token: String,

    /// Percentage of duplicate records to inject (0–50)
    #[arg(long, default_value = "10")]
    duplicates: u8,

    /// Random seed for reproducible output
    #[arg(long, default_value = "42")]
    seed: u64,

    /// Records per API batch
    #[arg(long, default_value = "100")]
    batch_size: usize,
}

#[derive(Debug, Clone, ValueEnum)]
enum EntityType {
    Customer,
    Vendor,
    Product,
    Material,
}

#[derive(Debug, Clone, ValueEnum)]
enum OutputFormat {
    Json,
    Csv,
    Api,
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    let entity_type_str = match cli.r#type {
        EntityType::Customer | EntityType::Material => "Customer",
        EntityType::Vendor   => "Vendor",
        EntityType::Product  => "Product",
    };

    // Validate args
    if cli.count == 0 {
        eprintln!("error: --count must be > 0");
        std::process::exit(1);
    }
    if cli.duplicates > 50 {
        eprintln!("error: --duplicates must be 0–50");
        std::process::exit(1);
    }

    eprintln!(
        "⚡  Generating {} {} records (seed={}, duplicates={}%)…",
        cli.count, entity_type_str, cli.seed, cli.duplicates
    );

    // Generate base entities
    let mut entities = match cli.r#type {
        EntityType::Customer | EntityType::Material => {
            CustomerGenerator::generate(cli.count, cli.seed)
        }
        EntityType::Vendor => VendorGenerator::generate(cli.count, cli.seed),
        EntityType::Product => ProductGenerator::generate(cli.count, cli.seed),
    };

    // Inject duplicates
    let dup_count = if cli.duplicates > 0 {
        let mutate_fn = match cli.r#type {
            EntityType::Customer | EntityType::Material => generators::customer::mutate_customer,
            EntityType::Vendor   => generators::vendor::mutate_vendor,
            EntityType::Product  => generators::product::mutate_product,
        };
        add_duplicates(&mut entities, cli.duplicates as f32, cli.seed, mutate_fn)
    } else {
        0
    };

    eprintln!(
        "✓  {} base records + {} duplicates = {} total",
        cli.count, dup_count, entities.len()
    );

    // Output
    match cli.output {
        OutputFormat::Json => {
            write_json(&entities, entity_type_str)?;
        }
        OutputFormat::Csv => {
            write_csv(&entities, entity_type_str)?;
        }
        OutputFormat::Api => {
            eprintln!("📤  Sending to {} in batches of {}…", cli.api_url, cli.batch_size);
            eprintln!();

            let mut summary = post_to_api(
                entities,
                entity_type_str,
                cli.tenant_id,
                &cli.api_url,
                &cli.auth_token,
                cli.batch_size,
            )
            .await?;

            summary.duplicates_injected = dup_count;
            print_summary(&summary);

            if summary.total_failed > 0 {
                eprintln!("⚠️  {} records failed — check the ingest service logs.", summary.total_failed);
                std::process::exit(1);
            }
        }
    }

    Ok(())
}
