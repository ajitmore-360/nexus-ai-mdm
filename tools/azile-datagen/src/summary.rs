use serde::{Deserialize, Serialize};

/// Aggregated result of a generation + ingest run.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct GenerationSummary {
    pub total_generated:    usize,
    pub total_created:      usize,
    pub total_skipped:      usize,
    pub total_failed:       usize,
    pub duplicates_injected: usize,
    pub batches_sent:       usize,
    pub duration_ms:        u64,
}

pub fn print_summary(summary: &GenerationSummary) {
    let width = 44usize;
    let bar   = "─".repeat(width);

    println!();
    println!("┌{}┐", bar);
    println!("│{:^width$}│", " Nexus DataGen — Run Summary ", width = width);
    println!("├{}┤", bar);
    println!("│  {:<28} {:>10}  │", "Entities generated:",     summary.total_generated);
    println!("│  {:<28} {:>10}  │", "Duplicates injected:",     summary.duplicates_injected);
    println!("├{}┤", bar);
    println!("│  {:<28} {:>10}  │", "Records created:",         summary.total_created);
    println!("│  {:<28} {:>10}  │", "Records skipped:",         summary.total_skipped);
    println!("│  {:<28} {:>10}  │", "Records failed:",          summary.total_failed);
    println!("├{}┤", bar);
    println!("│  {:<28} {:>10}  │", "Batches sent:",            summary.batches_sent);
    println!("│  {:<28} {:>9}ms  │", "Total duration:",          summary.duration_ms);
    println!("└{}┘", bar);
    println!();
}
