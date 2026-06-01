--
-- =========================================================
-- Nexus MDM Platform
-- Production Extension Initialization
-- File: 001_extensions.sql
-- =========================================================
--

BEGIN;

--
-- =========================================================
-- REQUIRED EXTENSIONS
-- =========================================================
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";
CREATE EXTENSION IF NOT EXISTS "btree_gin";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "citext";

--
-- =========================================================
-- EXTENSION COMMENTS
-- =========================================================
--

COMMENT ON EXTENSION "uuid-ossp"
IS 'UUID generation support';

COMMENT ON EXTENSION "pgcrypto"
IS 'Cryptographic functions and gen_random_uuid()';

COMMENT ON EXTENSION "vector"
IS 'pgvector extension for embeddings and semantic search';

COMMENT ON EXTENSION "pg_trgm"
IS 'Trigram similarity support for fuzzy matching';

COMMENT ON EXTENSION "btree_gin"
IS 'GIN support for scalar + JSON hybrid indexing';

COMMENT ON EXTENSION "btree_gist"
IS 'GiST support for advanced exclusion constraints';

COMMIT;