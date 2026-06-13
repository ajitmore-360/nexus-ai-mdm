use std::collections::HashMap;
use rand::{Rng, SeedableRng, seq::SliceRandom};
use serde_json::{json, Value};
use uuid::Uuid;

use super::EntityGenerator;

// ─────────────────────────────────────────────────────────────────────────────
// Static data tables
// ─────────────────────────────────────────────────────────────────────────────

static FIRST_NAMES: &[&str] = &[
    "James",    "Mary",     "John",    "Patricia",  "Robert",  "Jennifer",
    "Michael",  "Linda",    "William", "Barbara",   "David",   "Elizabeth",
    "Richard",  "Susan",    "Joseph",  "Jessica",   "Thomas",  "Sarah",
    "Charles",  "Karen",    "Daniel",  "Lisa",      "Matthew", "Nancy",
    "Anthony",  "Betty",    "Mark",    "Margaret",  "Donald",  "Sandra",
    "Steven",   "Ashley",   "Paul",    "Emily",     "Andrew",  "Donna",
    "Kenneth",  "Michelle", "Joshua",  "Carol",     "Kevin",   "Amanda",
    "Brian",    "Dorothy",  "George",  "Melissa",   "Timothy", "Deborah",
    "Ronald",   "Stephanie","Edward",  "Rebecca",   "Jason",   "Sharon",
    "Jeffrey",  "Laura",    "Ryan",    "Cynthia",   "Jacob",   "Kathleen",
    "Gary",     "Amy",      "Nicholas","Angela",    "Eric",    "Shirley",
    "Jonathan", "Anna",     "Stephen", "Brenda",    "Larry",   "Pamela",
    "Justin",   "Emma",     "Scott",   "Nicole",    "Brandon", "Helen",
    "Benjamin", "Samantha", "Samuel",  "Katherine", "Raymond", "Christine",
    "Gregory",  "Debra",    "Frank",   "Rachel",    "Alexander","Carolyn",
    "Patrick",  "Janet",    "Jack",    "Catherine", "Dennis",  "Maria",
    "Jerry",    "Heather",  "Tyler",   "Diane",     "Aaron",   "Julie",
    "Jose",     "Joyce",    "Henry",   "Victoria",  "Adam",    "Kelly",
    "Douglas",  "Christina","Nathan",  "Lauren",    "Peter",   "Joan",
    "Zachary",  "Evelyn",   "Kyle",    "Olivia",    "Noah",    "Judith",
];

static LAST_NAMES: &[&str] = &[
    "Smith",    "Johnson",  "Williams","Brown",     "Jones",   "Garcia",
    "Miller",   "Davis",    "Rodriguez","Martinez", "Hernandez","Lopez",
    "Gonzalez", "Wilson",   "Anderson","Thomas",    "Taylor",  "Moore",
    "Jackson",  "Martin",   "Lee",     "Perez",     "Thompson","White",
    "Harris",   "Sanchez",  "Clark",   "Ramirez",   "Lewis",   "Robinson",
    "Walker",   "Young",    "Allen",   "King",      "Wright",  "Scott",
    "Torres",   "Nguyen",   "Hill",    "Flores",    "Green",   "Adams",
    "Nelson",   "Baker",    "Hall",    "Rivera",    "Campbell","Mitchell",
    "Carter",   "Roberts",  "Gomez",   "Phillips",  "Evans",   "Turner",
    "Diaz",     "Parker",   "Cruz",    "Edwards",   "Collins", "Reyes",
    "Stewart",  "Morris",   "Morales", "Murphy",    "Cook",    "Rogers",
    "Gutierrez","Ortiz",    "Morgan",  "Cooper",    "Peterson","Bailey",
    "Reed",     "Kelly",    "Howard",  "Ramos",     "Kim",     "Cox",
    "Ward",     "Richardson","Watson", "Brooks",    "Chavez",  "Wood",
    "James",    "Bennett",  "Gray",    "Mendoza",   "Ruiz",    "Hughes",
    "Price",    "Alvarez",  "Castillo","Sanders",   "Patel",   "Myers",
    "Long",     "Ross",     "Foster",  "Jimenez",   "Powell",  "Jenkins",
    "Perry",    "Russell",  "Sullivan","Bell",      "Coleman", "Butler",
    "Henderson","Barnes",   "Gonzales","Fisher",    "Vasquez", "Simmons",
    "Romero",   "Jordan",   "Patterson","Alexander","Hamilton","Graham",
];

static COMPANY_PREFIXES: &[&str] = &[
    "Advanced", "Allied",   "American",  "Apex",      "Atlas",   "Beacon",
    "Blue",     "Bright",   "Capital",   "Cardinal",  "Central", "Century",
    "Crest",    "Crown",    "Cypress",   "Delta",     "Diamond", "Eagle",
    "Eastern",  "Elite",    "Empire",    "Endeavor",  "Everest", "Excel",
    "Falcon",   "First",    "Frontier",  "Galaxy",    "Genesis", "Global",
    "Golden",   "Grand",    "Granite",   "Greenfield","Griffin", "Harmony",
    "Heritage",  "Highland","Horizon",   "Impact",    "Inland",  "Integrated",
    "Keystone", "Liberty",  "Lincoln",   "Longview",  "Majestic","Maple",
    "Matrix",   "Metro",    "Midland",   "Milestone", "Modern",  "National",
    "Nexus",    "Nordic",   "Northern",  "Northwest", "Nova",    "Oak",
    "Omega",    "Onyx",     "Open",      "Pacific",   "Patriot", "Peak",
    "Pinnacle", "Pioneer",  "Platinum",  "Prime",     "Premier", "Pro",
    "Quantum",  "Rapid",    "Redwood",   "Reliable",  "River",   "Rockstar",
    "Sapphire", "Sentinel", "Signature", "Silver",    "Solar",   "Southern",
    "Spartan",  "Spectrum",  "Summit",   "Superior",  "Sure",    "Swift",
    "Synergy",  "Tara",     "Titan",     "Triumph",   "True",    "United",
    "Universal","Valor",    "Vector",    "Venture",   "Vertex",  "Vibe",
    "Viking",   "Vision",   "Vortex",    "Western",   "White",   "Zenith",
];

static INDUSTRIES: &[&str] = &[
    "Technologies", "Solutions",  "Industries", "Systems",    "Services",
    "Consulting",   "Logistics",  "Healthcare", "Financial",  "Energy",
    "Engineering",  "Analytics",  "Digital",    "Innovations","Partners",
    "Manufacturing","Distribution","Research",  "Capital",    "Ventures",
];

static COMPANY_SUFFIXES: &[&str] = &[
    "Inc.",  "LLC",   "Corp.", "Co.",   "Ltd.",
    "Group", "Holdings", "Enterprises", "International", "Associates",
];

static STREET_NAMES: &[&str] = &[
    "Main",         "Oak",          "Maple",        "Cedar",        "Elm",
    "Pine",         "Washington",   "Lincoln",      "Jefferson",    "Madison",
    "Franklin",     "Park",         "Lake",         "Hill",         "River",
    "View",         "Spring",       "Sunset",       "Forest",       "Valley",
    "Ridge",        "Meadow",       "Brook",        "Creek",        "Mill",
    "Church",       "School",       "College",      "University",   "Market",
    "Commerce",     "Industrial",   "Corporate",    "Technology",   "Innovation",
    "Enterprise",   "Business",     "Trade",        "Gateway",      "Center",
    "Harbor",       "Bay",          "Shore",        "Coast",        "Cove",
    "Orchard",      "Garden",       "Vineyard",     "Harvest",      "Meadowlark",
    "Crossroads",   "Junction",     "Parkway",      "Boulevard",    "Avenue",
    "Drive",        "Court",        "Place",        "Square",       "Circle",
    "Lane",         "Way",          "Trail",        "Path",         "Road",
    "Willowbrook",  "Cedarwood",    "Maplewood",    "Oakwood",      "Pinecrest",
    "Rosewood",     "Birchwood",    "Applewood",    "Dogwood",      "Elmwood",
    "Brookfield",   "Springfield",  "Greenfield",   "Fairfield",    "Westfield",
    "Northfield",   "Southfield",   "Plainfield",   "Bloomfield",   "Sheffield",
    "Highland",     "Lowland",      "Midland",      "Lakeland",     "Woodland",
    "Farmington",   "Burlington",   "Lexington",    "Arlington",    "Carrington",
    "Hamilton",     "Wellington",   "Remington",    "Pennington",   "Worthington",
];

static STREET_TYPES: &[&str] = &[
    "St", "Ave", "Blvd", "Rd", "Dr", "Ln", "Ct", "Pl", "Way", "Pkwy",
];

/// (city, state_abbrev, zip_prefix)
static CITIES: &[(&str, &str, &str)] = &[
    ("New York",       "NY", "100"),
    ("Los Angeles",    "CA", "900"),
    ("Chicago",        "IL", "606"),
    ("Houston",        "TX", "770"),
    ("Phoenix",        "AZ", "850"),
    ("Philadelphia",   "PA", "191"),
    ("San Antonio",    "TX", "782"),
    ("San Diego",      "CA", "921"),
    ("Dallas",         "TX", "752"),
    ("San Jose",       "CA", "951"),
    ("Austin",         "TX", "787"),
    ("Jacksonville",   "FL", "322"),
    ("Fort Worth",     "TX", "761"),
    ("Columbus",       "OH", "432"),
    ("Charlotte",      "NC", "282"),
    ("Indianapolis",   "IN", "462"),
    ("San Francisco",  "CA", "941"),
    ("Seattle",        "WA", "981"),
    ("Denver",         "CO", "802"),
    ("Nashville",      "TN", "372"),
    ("Oklahoma City",  "OK", "731"),
    ("El Paso",        "TX", "799"),
    ("Washington",     "DC", "200"),
    ("Las Vegas",      "NV", "891"),
    ("Louisville",     "KY", "402"),
    ("Baltimore",      "MD", "212"),
    ("Milwaukee",      "WI", "532"),
    ("Albuquerque",    "NM", "871"),
    ("Tucson",         "AZ", "857"),
    ("Fresno",         "CA", "937"),
    ("Sacramento",     "CA", "958"),
    ("Kansas City",    "MO", "641"),
    ("Mesa",           "AZ", "852"),
    ("Atlanta",        "GA", "303"),
    ("Omaha",          "NE", "681"),
    ("Colorado Springs","CO","809"),
    ("Raleigh",        "NC", "276"),
    ("Long Beach",     "CA", "908"),
    ("Virginia Beach", "VA", "234"),
    ("Minneapolis",    "MN", "554"),
    ("Tampa",          "FL", "336"),
    ("New Orleans",    "LA", "701"),
    ("Arlington",      "TX", "760"),
    ("Bakersfield",    "CA", "933"),
    ("Honolulu",       "HI", "968"),
    ("Anaheim",        "CA", "928"),
    ("Aurora",         "CO", "800"),
    ("Santa Ana",      "CA", "927"),
    ("Corpus Christi", "TX", "784"),
    ("Riverside",      "CA", "925"),
    ("Lexington",      "KY", "405"),
    ("St. Louis",      "MO", "631"),
    ("Pittsburgh",     "PA", "152"),
    ("Portland",       "OR", "972"),
    ("Cincinnati",     "OH", "452"),
];

static DOMAINS: &[&str] = &[
    "gmail.com", "yahoo.com", "outlook.com", "hotmail.com", "aol.com",
    "mail.com", "protonmail.com", "icloud.com", "zoho.com", "fastmail.com",
];

static INDUSTRY_CATEGORIES: &[&str] = &[
    "Technology",        "Healthcare",       "Finance",
    "Manufacturing",     "Retail",           "Energy",
    "Transportation",    "Real Estate",      "Education",
    "Construction",      "Agriculture",      "Telecommunications",
    "Media & Entertainment","Aerospace",     "Automotive",
    "Pharmaceuticals",   "Food & Beverage",  "Chemicals",
    "Professional Services","Government",
];

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

fn random_phone(rng: &mut impl Rng) -> String {
    let area:   u32 = rng.gen_range(200..999);
    let prefix: u32 = rng.gen_range(200..999);
    let line:   u32 = rng.gen_range(1000..9999);
    format!("+1{}{}{}", area, prefix, line)
}

fn tax_id(rng: &mut impl Rng) -> String {
    format!("{:02}-{:07}", rng.gen_range(10u32..99), rng.gen_range(1000000u32..9999999))
}

fn company_email(company: &str, domain: &str) -> String {
    let cleaned: String = company
        .chars()
        .filter(|c| c.is_alphanumeric())
        .collect::<String>()
        .to_lowercase();
    let short = &cleaned[..cleaned.len().min(20)];
    format!("contact@{}.{}", short, domain)
}

fn person_email(first: &str, last: &str, domain: &str) -> String {
    format!(
        "{}.{}@{}",
        first.to_lowercase(),
        last.to_lowercase(),
        domain
    )
}

fn website(company: &str) -> String {
    let cleaned: String = company
        .chars()
        .filter(|c| c.is_alphanumeric())
        .collect::<String>()
        .to_lowercase();
    let short = &cleaned[..cleaned.len().min(24)];
    format!("www.{}.com", short)
}

fn build_address(rng: &mut impl Rng) -> (String, String, String, String, String) {
    let number          = rng.gen_range(1u32..=9999);
    let street_name     = STREET_NAMES.choose(rng).unwrap();
    let street_type     = STREET_TYPES.choose(rng).unwrap();
    let (city, state, zip_prefix) = CITIES.choose(rng).unwrap();
    let zip_suffix: u32 = rng.gen_range(10..99);
    let zip             = format!("{}{:02}", zip_prefix, zip_suffix);
    let street          = format!("{} {} {}", number, street_name, street_type);
    (
        street,
        city.to_string(),
        state.to_string(),
        zip,
        "USA".to_string(),
    )
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomerGenerator
// ─────────────────────────────────────────────────────────────────────────────

pub struct CustomerGenerator;

impl EntityGenerator for CustomerGenerator {
    fn generate(count: usize, seed: u64) -> Vec<HashMap<String, Value>> {
        let mut rng = rand::rngs::StdRng::seed_from_u64(seed);
        let mut entities = Vec::with_capacity(count);

        for _ in 0..count {
            let first_name = *FIRST_NAMES.choose(&mut rng).unwrap();
            let last_name  = *LAST_NAMES.choose(&mut rng).unwrap();
            let prefix     = *COMPANY_PREFIXES.choose(&mut rng).unwrap();
            let industry   = *INDUSTRIES.choose(&mut rng).unwrap();
            let suffix     = *COMPANY_SUFFIXES.choose(&mut rng).unwrap();
            let company    = format!("{} {} {}", prefix, industry, suffix);

            let email_domain = *DOMAINS.choose(&mut rng).unwrap();
            let email        = person_email(first_name, last_name, email_domain);
            let phone        = random_phone(&mut rng);
            let (street, city, state, zip, country) = build_address(&mut rng);
            let industry_cat = *INDUSTRY_CATEGORIES.choose(&mut rng).unwrap();

            // Revenue: $1M – $500M in $500K increments
            let revenue_units = rng.gen_range(2u64..=1000);
            let annual_revenue = revenue_units * 500_000;

            let employee_count: u32 = rng.gen_range(10..=50_000);
            let founded_year:   u32 = rng.gen_range(1950..=2020);
            let comp_email         = company_email(&company, email_domain);
            let web                = website(&company);
            let tax                = tax_id(&mut rng);

            let mut m = HashMap::new();
            m.insert("id".into(),               json!(Uuid::new_v4().to_string()));
            m.insert("first_name".into(),        json!(first_name));
            m.insert("last_name".into(),         json!(last_name));
            m.insert("company_name".into(),      json!(company));
            m.insert("email".into(),             json!(email));
            m.insert("company_email".into(),     json!(comp_email));
            m.insert("phone".into(),             json!(phone));
            m.insert("address_line1".into(),     json!(street));
            m.insert("city".into(),              json!(city));
            m.insert("state".into(),             json!(state));
            m.insert("zip_code".into(),          json!(zip));
            m.insert("country".into(),           json!(country));
            m.insert("tax_id".into(),            json!(tax));
            m.insert("annual_revenue".into(),    json!(annual_revenue));
            m.insert("employee_count".into(),    json!(employee_count));
            m.insert("industry".into(),          json!(industry_cat));
            m.insert("website".into(),           json!(web));
            m.insert("founded_year".into(),      json!(founded_year));
            m.insert("source_system".into(),     json!("nexus-datagen"));
            entities.push(m);
        }
        entities
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Duplicate mutation
// ─────────────────────────────────────────────────────────────────────────────

/// Apply surface-level noise to a customer record to simulate real duplicates.
pub fn mutate_customer(
    original: &HashMap<String, Value>,
    rng:      &mut rand::rngs::StdRng,
) -> HashMap<String, Value> {
    let mut dup = original.clone();

    // Give the duplicate a new source ID so it appears to be a separate record.
    dup.insert("id".into(), json!(Uuid::new_v4().to_string()));

    // Variation 1 — company name suffix swap
    if let Some(Value::String(cn)) = original.get("company_name") {
        let new_suffix = *COMPANY_SUFFIXES.choose(rng).unwrap();
        // strip any existing suffix and append the new one
        let base: String = cn
            .split_whitespace()
            .filter(|w| !COMPANY_SUFFIXES.contains(w))
            .collect::<Vec<_>>()
            .join(" ");
        dup.insert("company_name".into(), json!(format!("{} {}", base, new_suffix)));
    }

    // Variation 2 — reformat phone  (+1XXXXXXXXXX → (XXX) XXX-XXXX)
    if let Some(Value::String(ph)) = original.get("phone") {
        let digits: String = ph.chars().filter(|c| c.is_ascii_digit()).collect();
        if digits.len() == 11 {
            let d = &digits[1..]; // strip leading 1
            dup.insert(
                "phone".into(),
                json!(format!("({}) {}-{}", &d[0..3], &d[3..6], &d[6..10])),
            );
        }
    }

    // Variation 3 — email capitalisation change
    if let Some(Value::String(em)) = original.get("email") {
        // Capitalise the local part
        if let Some((local, domain)) = em.split_once('@') {
            let new_local: String = local
                .chars()
                .enumerate()
                .map(|(i, c)| if i % 2 == 0 { c.to_ascii_uppercase() } else { c })
                .collect();
            dup.insert("email".into(), json!(format!("{}@{}", new_local, domain)));
        }
    }

    // Variation 4 — abbreviated address (drop unit, use short form)
    if let Some(Value::String(addr)) = original.get("address_line1") {
        let parts: Vec<&str> = addr.splitn(3, ' ').collect();
        if parts.len() == 3 {
            // Keep number + first letter of street name + type abbreviated
            let abbrev = format!("{} {}. {}", parts[0], &parts[1][..1], parts[2]);
            dup.insert("address_line1".into(), json!(abbrev));
        }
    }

    dup
}
