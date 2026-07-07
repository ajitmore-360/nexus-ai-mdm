-- Migration 0014: Global postal code reference table for cross-field validation
-- ─────────────────────────────────────────────────────────────────────────────
-- This table is tenant-independent (reference data).
-- Production: load full GeoNames postal_codes.zip via the seed script at
--   scripts/seed_postal_codes.sh  (downloads ~50 MB, inserts ~2 M rows).
-- Dev/CI:     a representative sample is seeded here for smoke-testing.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS core_mdm.geo_postal_codes (
    id            BIGSERIAL PRIMARY KEY,
    country_code  CHAR(2)      NOT NULL,        -- ISO 3166-1 alpha-2
    postal_code   TEXT         NOT NULL,
    place_name    TEXT         NOT NULL,         -- city / locality
    admin1_name   TEXT         NOT NULL DEFAULT '', -- state / province
    admin2_name   TEXT         NOT NULL DEFAULT '', -- county / district
    latitude      NUMERIC(9,6),
    longitude     NUMERIC(9,6)
);

CREATE INDEX IF NOT EXISTS idx_gpc_country_postal
    ON core_mdm.geo_postal_codes (country_code, postal_code);

CREATE INDEX IF NOT EXISTS idx_gpc_country_city
    ON core_mdm.geo_postal_codes (country_code, lower(place_name));

-- ─────────────────────────────────────────────────────────────────────────────
-- Sample seed data (enough for smoke-testing common rules)
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO core_mdm.geo_postal_codes (country_code, postal_code, place_name, admin1_name) VALUES
-- United Kingdom
('GB', 'SW1A 1AA', 'London',     'England'),
('GB', 'SW1A 2AA', 'London',     'England'),
('GB', 'EC1A 1BB', 'London',     'England'),
('GB', 'M1 1AE',   'Manchester', 'England'),
('GB', 'B1 1BB',   'Birmingham', 'England'),
('GB', 'EH1 1YZ',  'Edinburgh',  'Scotland'),
-- United States
('US', '10001',    'New York',      'New York'),
('US', '10002',    'New York',      'New York'),
('US', '90001',    'Los Angeles',   'California'),
('US', '60601',    'Chicago',       'Illinois'),
('US', '77001',    'Houston',       'Texas'),
('US', '85001',    'Phoenix',       'Arizona'),
-- Germany
('DE', '10115',    'Berlin',        'Berlin'),
('DE', '20095',    'Hamburg',       'Hamburg'),
('DE', '80331',    'Munich',        'Bavaria'),
('DE', '50667',    'Cologne',       'North Rhine-Westphalia'),
-- India
('IN', '110001',   'New Delhi',     'Delhi'),
('IN', '400001',   'Mumbai',        'Maharashtra'),
('IN', '560001',   'Bangalore',     'Karnataka'),
('IN', '600001',   'Chennai',       'Tamil Nadu'),
-- France
('FR', '75001',    'Paris',         'Ile-de-France'),
('FR', '75008',    'Paris',         'Ile-de-France'),
('FR', '69001',    'Lyon',          'Auvergne-Rhone-Alpes'),
-- Australia
('AU', '2000',     'Sydney',        'New South Wales'),
('AU', '3000',     'Melbourne',     'Victoria'),
('AU', '4000',     'Brisbane',      'Queensland'),
-- Canada
('CA', 'M5H 2N2',  'Toronto',       'Ontario'),
('CA', 'H3A 0G4',  'Montreal',      'Quebec'),
('CA', 'V6B 1A1',  'Vancouver',     'British Columbia'),
-- Singapore
('SG', '018960',   'Singapore',     'Singapore'),
('SG', '048583',   'Singapore',     'Singapore')
ON CONFLICT DO NOTHING;
