use std::collections::HashMap;
use rand::{Rng, SeedableRng, seq::SliceRandom};
use serde_json::{json, Value};
use uuid::Uuid;

use super::EntityGenerator;

// ─────────────────────────────────────────────────────────────────────────────
// Static data
// ─────────────────────────────────────────────────────────────────────────────

static PRODUCT_CATEGORIES: &[(&str, &[&str])] = &[
    ("Electronics", &[
        "Processors",       "Memory Modules",    "Power Supplies",
        "Circuit Boards",   "Sensors",           "Displays",
        "Connectors",       "Cables",            "Switches",       "Controllers",
    ]),
    ("Mechanical", &[
        "Bearings",         "Fasteners",         "Seals",
        "Springs",          "Gears",             "Shafts",
        "Brackets",         "Housings",          "Gaskets",        "Bushings",
    ]),
    ("Chemical", &[
        "Solvents",         "Adhesives",         "Lubricants",
        "Coatings",         "Resins",            "Catalysts",
        "Cleaning Agents",  "Reagents",          "Polymers",       "Dyes",
    ]),
    ("Packaging", &[
        "Corrugated Boxes", "Bubble Wrap",       "Stretch Film",
        "Foam Inserts",     "Pallets",           "Labels",
        "Tape",             "Void Fill",         "Bags",           "Containers",
    ]),
    ("Raw Materials", &[
        "Steel Sheet",      "Aluminum Bar",      "Copper Wire",
        "Plastic Pellets",  "Rubber Sheet",      "Glass Fiber",
        "Carbon Fiber",     "Titanium Rod",      "Brass Tube",     "Stainless Coil",
    ]),
    ("Safety", &[
        "Hard Hats",        "Safety Glasses",    "Gloves",
        "Respirators",      "Safety Vests",      "Ear Protection",
        "Steel-Toe Boots",  "Face Shields",      "First Aid Kits", "Fire Extinguishers",
    ]),
    ("Office Supplies", &[
        "Printer Paper",    "Toner Cartridges",  "Pens & Pencils",
        "Binders",          "Notebooks",         "Envelopes",
        "Staples",          "Tape Dispensers",   "Folders",        "Labels",
    ]),
    ("IT Hardware", &[
        "Laptops",          "Monitors",          "Keyboards",
        "Mice",             "Network Switches",  "Patch Panels",
        "Server Racks",     "UPS Units",         "Hard Drives",    "SSDs",
    ]),
];

static MANUFACTURERS: &[&str] = &[
    "Acme Manufacturing", "Allied Components",  "Atlas Industrial",
    "Beta Technologies",  "Core Materials",     "Delta Systems",
    "Eagle Components",   "Falcon Industries",  "Global Parts",
    "Granite Manufacturing","Heritage Supply",  "Horizon Industries",
    "Keystone Components","Legacy Materials",   "Nexus Manufacturing",
    "Pacific Industrial", "Patriot Components", "Pinnacle Parts",
    "Prime Manufacturing","Quantum Components", "Rapid Industries",
    "Reliable Parts",     "Sentinel Supply",    "Sigma Manufacturing",
    "Summit Components",  "Superior Materials", "Titan Industries",
    "United Components",  "Valor Manufacturing","Zenith Industries",
];

static UOMS: &[&str] = &[
    "EA",   // Each
    "KG",   // Kilogram
    "LB",   // Pound
    "M",    // Meter
    "L",    // Liter
    "FT",   // Foot
    "IN",   // Inch
    "GAL",  // Gallon
    "BOX",  // Box
    "ROLL", // Roll
    "CASE", // Case
    "PKG",  // Package
];

static DESCRIPTION_TEMPLATES: &[&str] = &[
    "High-performance {sub} designed for industrial applications. Meets industry standards for quality and reliability.",
    "Commercial-grade {sub} suitable for demanding environments. Manufactured to precise tolerances.",
    "Heavy-duty {sub} with superior durability. Ideal for manufacturing and production use.",
    "Standard {sub} for general-purpose applications. Cost-effective solution for everyday operational needs.",
    "Premium {sub} with enhanced specifications. Provides consistent performance in critical processes.",
    "Industrial-strength {sub} built for continuous operation. Reduces maintenance requirements and downtime.",
    "Certified {sub} meeting ISO quality standards. Trusted by leading manufacturers worldwide.",
    "Precision-engineered {sub} for exact fitment. Compatible with standard industry specifications.",
    "Professional-grade {sub} for commercial use. Delivers reliable performance across varied conditions.",
    "Engineered {sub} optimized for efficiency. Reduces operational costs while maintaining quality output.",
];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

fn sku(rng: &mut impl Rng) -> String {
    let n: u32 = rng.gen_range(10000..=99999);
    format!("SKU-{}", n)
}

fn mfr_part_number(rng: &mut impl Rng, mfr: &str) -> String {
    let prefix: String = mfr
        .split_whitespace()
        .map(|w| w.chars().next().unwrap_or('X'))
        .collect();
    let n: u32 = rng.gen_range(100000..=999999);
    format!("{}-{}", prefix.to_uppercase(), n)
}

fn unit_price(rng: &mut impl Rng, category: &str) -> (f64, f64) {
    let (base_min, base_max): (f64, f64) = match category {
        "Electronics"    => (5.00,    2500.00),
        "Mechanical"     => (0.50,     500.00),
        "Chemical"       => (2.00,     300.00),
        "Packaging"      => (0.10,      50.00),
        "Raw Materials"  => (1.00,     200.00),
        "Safety"         => (5.00,     250.00),
        "Office Supplies"=> (0.25,     150.00),
        "IT Hardware"    => (50.00,  5000.00),
        _                => (1.00,     500.00),
    };
    let cost: f64  = rng.gen_range(base_min..base_max);
    let cost        = (cost * 100.0).round() / 100.0;
    let margin: f64 = rng.gen_range(1.10..1.50); // 10-50% markup
    let list        = (cost * margin * 100.0).round() / 100.0;
    (cost, list)
}

// ─────────────────────────────────────────────────────────────────────────────
// ProductGenerator
// ─────────────────────────────────────────────────────────────────────────────

pub struct ProductGenerator;

impl EntityGenerator for ProductGenerator {
    fn generate(count: usize, seed: u64) -> Vec<HashMap<String, Value>> {
        let mut rng      = rand::rngs::StdRng::seed_from_u64(seed);
        let mut entities = Vec::with_capacity(count);

        for _ in 0..count {
            let (category, subcats)  = *PRODUCT_CATEGORIES.choose(&mut rng).unwrap();
            let sub_category         = *subcats.choose(&mut rng).unwrap();
            let manufacturer         = *MANUFACTURERS.choose(&mut rng).unwrap();
            let uom                  = *UOMS.choose(&mut rng).unwrap();
            let product_sku          = sku(&mut rng);
            let mfr_pn               = mfr_part_number(&mut rng, manufacturer);
            let (unit_price, list_price) = unit_price(&mut rng, category);

            // Product name: "{Manufacturer short} {SubCategory} {SKU suffix}"
            let mfr_short: &str = manufacturer.split_whitespace().next().unwrap_or("Generic");
            let product_name = format!("{} {} ({})", mfr_short, sub_category, &product_sku[4..]);

            // Description from template
            let tmpl = *DESCRIPTION_TEMPLATES.choose(&mut rng).unwrap();
            let description = tmpl.replace("{sub}", sub_category);

            // 90% active, 10% inactive
            let active: bool = rng.gen_range(0..10) < 9;

            let mut m = HashMap::new();
            m.insert("id".into(),                    json!(Uuid::new_v4().to_string()));
            m.insert("product_name".into(),          json!(product_name));
            m.insert("sku".into(),                   json!(product_sku));
            m.insert("category".into(),              json!(category));
            m.insert("sub_category".into(),          json!(sub_category));
            m.insert("uom".into(),                   json!(uom));
            m.insert("unit_price".into(),            json!(unit_price));
            m.insert("list_price".into(),            json!(list_price));
            m.insert("manufacturer_name".into(),     json!(manufacturer));
            m.insert("manufacturer_part_number".into(), json!(mfr_pn));
            m.insert("description".into(),           json!(description));
            m.insert("active".into(),                json!(active));
            m.insert("source_system".into(),         json!("nexus-datagen"));
            entities.push(m);
        }
        entities
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duplicate mutation
// ─────────────────────────────────────────────────────────────────────────────

pub fn mutate_product(
    original: &HashMap<String, Value>,
    rng:      &mut rand::rngs::StdRng,
) -> HashMap<String, Value> {
    let mut dup = original.clone();
    dup.insert("id".into(), json!(Uuid::new_v4().to_string()));

    // Slightly alter product name capitalisation / spacing
    if let Some(Value::String(pn)) = original.get("product_name") {
        let suffixes = ["Assembly", "Unit", "Component", "Module"];
        let sfx = suffixes.choose(rng).unwrap();
        dup.insert("product_name".into(), json!(format!("{} {}", pn, sfx)));
    }

    // Change UOM to an alternative but compatible one
    let alt_uoms: &[&str] = &["EA", "PC", "UNIT", "CS"];
    let new_uom = *alt_uoms.choose(rng).unwrap();
    dup.insert("uom".into(), json!(new_uom));

    // Slightly vary unit_price (within ±5%)
    if let Some(Value::Number(up)) = original.get("unit_price") {
        if let Some(f) = up.as_f64() {
            let factor: f64 = rng.gen_range(0.95..1.05);
            let new_price   = (f * factor * 100.0).round() / 100.0;
            dup.insert("unit_price".into(), json!(new_price));
        }
    }

    dup
}
