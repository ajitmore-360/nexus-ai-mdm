use std::collections::HashMap;
use rand::{Rng, SeedableRng, seq::SliceRandom};
use serde_json::{json, Value};
use uuid::Uuid;

use super::EntityGenerator;

// ─────────────────────────────────────────────────────────────────────────────
// Static data
// ─────────────────────────────────────────────────────────────────────────────

static VENDOR_PREFIXES: &[&str] = &[
    "Acme",        "Allied",      "American",    "Apex",        "Atlas",
    "Beacon",      "Blueprint",   "Catalyst",    "Central",     "Core",
    "Crestline",   "Crown",       "Delta",       "Dimension",   "Eagle",
    "Eastside",    "Envoy",       "Falcon",      "First",       "Fleet",
    "Frontier",    "Galactic",    "Genesis",     "Global",      "Granite",
    "Guardian",    "Harbor",      "Heritage",    "Highland",    "Horizon",
    "Icon",        "Impact",      "Inland",      "Interlink",   "Interstate",
    "Keystone",    "Legacy",      "Liberty",     "Lynx",        "Mainstay",
    "Metro",       "Milestone",   "National",    "Nexus",       "Nordic",
    "Onyx",        "Pacific",     "Patriot",     "Peak",        "Pinnacle",
    "Pioneer",     "Platinum",    "Prime",       "Primus",      "Quantum",
    "Rapid",       "Reliable",    "Reliant",     "Riverstone",  "Rockfield",
    "Sapphire",    "Sentinel",    "Signature",   "Silver",      "Summit",
    "Superior",    "Titan",       "Triumph",     "United",      "Universal",
    "Valor",       "Vector",      "Venture",     "Vertex",      "Viking",
    "Vision",      "Vortex",      "Western",     "Whitestone",  "Zenith",
];

static VENDOR_INDUSTRIES: &[&str] = &[
    "Supply",      "Materials",   "Components",  "Resources",   "Logistics",
    "Distribution","Equipment",   "Systems",     "Services",    "Solutions",
    "Technologies","Industrial",  "Commercial",  "Procurement", "Sourcing",
];

static VENDOR_LEGAL_SUFFIXES: &[&str] = &[
    "Inc.", "LLC", "Corp.", "Co.", "Ltd.", "LP", "LLP", "Holdings LLC",
];

static VENDOR_CATEGORIES: &[&str] = &[
    "Raw Materials",        "Packaging",          "Maintenance & Repair",
    "Facilities",           "IT Hardware",        "IT Software",
    "Professional Services","Logistics & Freight","Marketing & Advertising",
    "Office Supplies",      "Capital Equipment",  "Utilities",
    "Chemicals",            "Safety Equipment",   "Consulting",
];

static PAYMENT_TERMS: &[&str] = &[
    "Net30", "Net60", "Net90", "Net15", "2/10 Net30", "COD", "Net45",
];

static CERTIFICATIONS: &[&str] = &[
    "ISO9001",  "ISO14001", "ISO27001", "SOX",      "GDPR",
    "HIPAA",    "PCI-DSS",  "SOC2",     "CMMC",     "AS9100",
    "IATF16949","FSSC22000","GMP",
];

static STREET_NAMES: &[&str] = &[
    "Industrial",   "Commerce",     "Business",     "Enterprise",    "Technology",
    "Corporate",    "Logistics",    "Trade",        "Manufacturing", "Warehouse",
    "Distribution", "Gateway",      "Center",       "Park",          "Ridge",
    "Valley",       "Summit",       "Harbor",       "Bay",           "Shore",
    "Main",         "Oak",          "Maple",        "Cedar",         "Pine",
    "Washington",   "Lincoln",      "Jefferson",    "Franklin",      "Market",
];

static STREET_TYPES: &[&str] = &[
    "St", "Ave", "Blvd", "Rd", "Dr", "Ln", "Ct", "Pl", "Way", "Pkwy",
];

static CITIES: &[(&str, &str, &str)] = &[
    ("Chicago",        "IL", "606"),
    ("Houston",        "TX", "770"),
    ("Detroit",        "MI", "482"),
    ("Columbus",       "OH", "432"),
    ("Indianapolis",   "IN", "462"),
    ("Memphis",        "TN", "381"),
    ("Louisville",     "KY", "402"),
    ("Baltimore",      "MD", "212"),
    ("Milwaukee",      "WI", "532"),
    ("Kansas City",    "MO", "641"),
    ("Atlanta",        "GA", "303"),
    ("Dallas",         "TX", "752"),
    ("Phoenix",        "AZ", "850"),
    ("Denver",         "CO", "802"),
    ("Seattle",        "WA", "981"),
    ("Minneapolis",    "MN", "554"),
    ("Tampa",          "FL", "336"),
    ("St. Louis",      "MO", "631"),
    ("Pittsburgh",     "PA", "152"),
    ("Cincinnati",     "OH", "452"),
];

static DOMAINS: &[&str] = &[
    "vendor.com",     "supply.net",    "corporate.org",
    "bizmail.com",    "enterprise.net","procurement.io",
    "sourcing.com",   "logistics.net", "supplies.org",
    "materials.com",
];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

fn vendor_code(rng: &mut impl Rng) -> String {
    let n: u32 = rng.gen_range(10000..=99999);
    format!("VEND-{}", n)
}

fn tax_id(rng: &mut impl Rng) -> String {
    format!("{:02}-{:07}", rng.gen_range(10u32..99), rng.gen_range(1000000u32..9999999))
}

fn masked_bank(rng: &mut impl Rng) -> String {
    let last4: u32 = rng.gen_range(1000..=9999);
    format!("XXXX-XXXX-XXXX-{}", last4)
}

fn random_phone(rng: &mut impl Rng) -> String {
    let area:   u32 = rng.gen_range(200..999);
    let prefix: u32 = rng.gen_range(200..999);
    let line:   u32 = rng.gen_range(1000..9999);
    format!("+1{}{}{}", area, prefix, line)
}

fn build_address(rng: &mut impl Rng) -> (String, String, String, String) {
    let number      = rng.gen_range(1u32..=9999);
    let street_name = STREET_NAMES.choose(rng).unwrap();
    let street_type = STREET_TYPES.choose(rng).unwrap();
    let (city, state, zip_prefix) = CITIES.choose(rng).unwrap();
    let zip_suffix: u32 = rng.gen_range(10..99);
    let zip         = format!("{}{:02}", zip_prefix, zip_suffix);
    let street      = format!("{} {} {}", number, street_name, street_type);
    (street, city.to_string(), state.to_string(), zip)
}

fn vendor_email(vendor: &str, domain: &str) -> String {
    let cleaned: String = vendor
        .chars()
        .filter(|c| c.is_alphanumeric())
        .collect::<String>()
        .to_lowercase();
    let short = &cleaned[..cleaned.len().min(20)];
    format!("procurement@{}.{}", short, domain)
}

fn website(vendor: &str) -> String {
    let cleaned: String = vendor
        .chars()
        .filter(|c| c.is_alphanumeric())
        .collect::<String>()
        .to_lowercase();
    let short = &cleaned[..cleaned.len().min(24)];
    format!("www.{}.com", short)
}

// ─────────────────────────────────────────────────────────────────────────────
// VendorGenerator
// ─────────────────────────────────────────────────────────────────────────────

pub struct VendorGenerator;

impl EntityGenerator for VendorGenerator {
    fn generate(count: usize, seed: u64) -> Vec<HashMap<String, Value>> {
        let mut rng     = rand::rngs::StdRng::seed_from_u64(seed);
        let mut entities = Vec::with_capacity(count);

        for _ in 0..count {
            let prefix   = *VENDOR_PREFIXES.choose(&mut rng).unwrap();
            let industry = *VENDOR_INDUSTRIES.choose(&mut rng).unwrap();
            let legal_sfx= *VENDOR_LEGAL_SUFFIXES.choose(&mut rng).unwrap();
            let vendor_name = format!("{} {}", prefix, industry);
            let legal_name  = format!("{} {} {}", prefix, industry, legal_sfx);

            let code    = vendor_code(&mut rng);
            let cat     = *VENDOR_CATEGORIES.choose(&mut rng).unwrap();
            let terms   = *PAYMENT_TERMS.choose(&mut rng).unwrap();
            let domain  = *DOMAINS.choose(&mut rng).unwrap();
            let email   = vendor_email(&vendor_name, domain);
            let phone   = random_phone(&mut rng);
            let web     = website(&vendor_name);
            let tax     = tax_id(&mut rng);
            let bank    = masked_bank(&mut rng);

            // 1-3 certifications
            let cert_count  = rng.gen_range(1usize..=3);
            let certs: Vec<&str> = CERTIFICATIONS
                .choose_multiple(&mut rng, cert_count)
                .copied()
                .collect();
            let cert_str = certs.join(", ");

            let (street, city, state, zip) = build_address(&mut rng);

            // Annual spend $10K – $10M
            let annual_spend = rng.gen_range(10_000u64..=10_000_000);

            let mut m = HashMap::new();
            m.insert("id".into(),              json!(Uuid::new_v4().to_string()));
            m.insert("vendor_name".into(),     json!(vendor_name));
            m.insert("legal_name".into(),      json!(legal_name));
            m.insert("vendor_code".into(),     json!(code));
            m.insert("category".into(),        json!(cat));
            m.insert("payment_terms".into(),   json!(terms));
            m.insert("tax_id".into(),          json!(tax));
            m.insert("address_line1".into(),   json!(street));
            m.insert("city".into(),            json!(city));
            m.insert("state".into(),           json!(state));
            m.insert("zip_code".into(),        json!(zip));
            m.insert("country".into(),         json!("USA"));
            m.insert("phone".into(),           json!(phone));
            m.insert("email".into(),           json!(email));
            m.insert("website".into(),         json!(web));
            m.insert("bank_account".into(),    json!(bank));
            m.insert("certifications".into(),  json!(cert_str));
            m.insert("annual_spend".into(),    json!(annual_spend));
            m.insert("source_system".into(),   json!("nexus-datagen"));
            entities.push(m);
        }
        entities
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duplicate mutation
// ─────────────────────────────────────────────────────────────────────────────

static VENDOR_SUFFIXES_FOR_MUTATION: &[&str] = &[
    "Inc.", "LLC", "Corp.", "Co.", "Ltd.",
];

pub fn mutate_vendor(
    original: &HashMap<String, Value>,
    rng:      &mut rand::rngs::StdRng,
) -> HashMap<String, Value> {
    let mut dup = original.clone();
    dup.insert("id".into(), json!(Uuid::new_v4().to_string()));

    // Swap legal suffix
    if let Some(Value::String(ln)) = original.get("legal_name") {
        let new_sfx = *VENDOR_SUFFIXES_FOR_MUTATION.choose(rng).unwrap();
        let base: String = ln
            .split_whitespace()
            .filter(|w| !VENDOR_SUFFIXES_FOR_MUTATION.contains(w) && !["Holdings", "LP", "LLP"].contains(w))
            .collect::<Vec<_>>()
            .join(" ");
        dup.insert("legal_name".into(), json!(format!("{} {}", base, new_sfx)));
    }

    // Phone format change
    if let Some(Value::String(ph)) = original.get("phone") {
        let digits: String = ph.chars().filter(|c| c.is_ascii_digit()).collect();
        if digits.len() == 11 {
            let d = &digits[1..];
            dup.insert(
                "phone".into(),
                json!(format!("{}-{}-{}", &d[0..3], &d[3..6], &d[6..10])),
            );
        }
    }

    // Email domain variation
    if let Some(Value::String(em)) = original.get("email") {
        if let Some((local, _domain)) = em.split_once('@') {
            dup.insert("email".into(), json!(format!("{}@vendor-corp.com", local)));
        }
    }

    dup
}
