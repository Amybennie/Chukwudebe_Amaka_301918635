-- =============================================================================
-- partition.sql - Portfolio 5
-- Convert the rent_instalment table from a flat heap into a RANGE (per academic session)
-- PARTITIONED table.
--
-- Student : Amaka Benedicta Chukwudebe
-- Matric  : 2026/A/MIT/0517
-- Course  : MIT 8103 Advanced Database Systems (Miva Open University)
-- Case    : CampusNest - Private Student Accommodation Booking
--
-- Why partition rent_instalment?
--   Portfolio 1's bulk_generator.py creates 100,000+ rent_instalment rows
--   spanning three academic years. A single flat heap becomes painful to
--   back up, archive, and query by date. Partitioning by due_date month
--   means:
--     * queries that filter on a date range scan only the relevant month
--       partitions (partition pruning),
--     * old months can be detached and archived cheaply
--       (ALTER TABLE ... DETACH PARTITION),
--     * VACUUM / REINDEX run per-month instead of on one giant heap.
--
-- Approach: PARTITION BY RANGE (due_date)
--   * Primary key on the new parent MUST include the partition key
--     (PG requires this), so PK = (instalment_id, due_date).
--   * one partition per academic session (Sept-Sept) is created, covering all data:
--     24 months in the past ... 12 months in the future.
--   * A DEFAULT partition catches any stray out-of-range row.
--
-- Run this through run_p5.sh, or directly with:
--   sudo runuser -u postgres -- psql -d campusnest \
--       -v ON_ERROR_STOP=1 -f portfolio-5-distributed-cloud/partition.sql
--
-- ON_ERROR_STOP is set by run_p5.sh so any error halts the script.
-- The script is designed to run ONCE. If you need to re-run it, drop the
-- campusnest database and re-run Portfolio 1 first.
-- =============================================================================

\set ON_ERROR_STOP on

\echo '============================================================'
\echo ' Portfolio 5 - partition.sql'
\echo ' Convert rent_instalment to a table partitioned by academic session.'
\echo ' Student: Amaka Benedicta Chukwudebe (2026/A/MIT/0517)'
\echo '============================================================'
\echo ''

-- ---------------------------------------------------------------------------
-- Step 1: Rename the existing rent_instalment to rent_instalment_old.
--         The data stays; only the name changes. We then drop the old
--         constraint and index NAMES so they do not collide with the names
--         the new partitioned table will use (rent_instalment_pkey etc.).
--         The old table's rows are still readable for the copy in Step 5.
-- ---------------------------------------------------------------------------
\echo '[Step 1] Rename the existing rent_instalment to rent_instalment_old'

ALTER TABLE rent_instalment RENAME TO rent_instalment_old;

-- Drop the FK constraint on the OLD table so the new table can reuse the
-- standard FK name rent_instalment_tenancy_id_fkey.
ALTER TABLE rent_instalment_old
    DROP CONSTRAINT IF EXISTS rent_instalment_tenancy_id_fkey;

-- Drop the old PK constraint + secondary indexes so their names are free.
ALTER TABLE rent_instalment_old DROP CONSTRAINT IF EXISTS rent_instalment_pkey;
DROP INDEX IF EXISTS rent_instalment_tenancy_id_idx;
DROP INDEX IF EXISTS rent_instalment_due_date_idx;
DROP INDEX IF EXISTS rent_instalment_paid_at_idx;
DROP INDEX IF EXISTS rent_instalment_status_idx;
DROP INDEX IF EXISTS rent_instalment_tenancy_due_idx;

\echo '  -> old table renamed; old constraint/index names cleared.'
\echo ''

-- ---------------------------------------------------------------------------
-- Step 2: Create the new partitioned parent.
--         PARTITION BY RANGE (due_date).
--         The PRIMARY KEY on a partitioned table MUST include the
--         partition key, so PK = (instalment_id, due_date).
-- ---------------------------------------------------------------------------
\echo '[Step 2] Create the new partitioned parent (PARTITION BY RANGE on due_date)'

CREATE TABLE rent_instalment (
    instalment_id BIGSERIAL,
    tenancy_id    BIGINT      NOT NULL,
    due_date      DATE        NOT NULL,
    amount_ngn    NUMERIC(12,2) NOT NULL CHECK (amount_ngn > 0),
    paid_at       TIMESTAMPTZ,
    status        TEXT        NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','overdue')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (instalment_id, due_date)
) PARTITION BY RANGE (due_date);

\echo '  -> partitioned parent created with PK (instalment_id, due_date).'
\echo ''

-- ---------------------------------------------------------------------------
-- Step 3: Create one partition per academic session (see the DO block).
--         Range: first session in the data -> the session after the last one.
--         Each partition is named rent_instalment_YYYY_MM (e.g.
--         rent_instalment_2026_09). The upper bound of each partition is
--         the first day of the NEXT month (RANGE partitions are
--         [lower, upper) - lower inclusive, upper exclusive).
-- ---------------------------------------------------------------------------
\echo '[Step 3] Create one partition per ACADEMIC SESSION (1 Sept -> 1 Sept),'
\echo '         covering every due_date in the data plus the next session'
-- Instalments fall due in Sept/Jan/Mar/May, so monthly partitions would be
-- mostly empty. One partition per session matches how CampusNest works:
-- reports are per session, and a finished session can be DETACHed and archived.
DO $$
DECLARE
    first_year INT;
    last_year  INT;
    y          INT;
BEGIN
    SELECT EXTRACT(YEAR FROM min(due_date) - INTERVAL '8 months')::int,
           EXTRACT(YEAR FROM max(due_date) - INTERVAL '8 months')::int + 1
      INTO first_year, last_year
      FROM rent_instalment_old;
    FOR y IN first_year..last_year LOOP
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF rent_instalment FOR VALUES FROM (%L) TO (%L)',
            'rent_instalment_s' || y || '_' || to_char((y + 1) % 100, 'FM00'),
            make_date(y, 9, 1), make_date(y + 1, 9, 1));
        RAISE NOTICE 'partition for session %/% created', y, y + 1;
    END LOOP;
END $$;

\echo '[Step 4] Create the DEFAULT partition (safety net - should stay EMPTY)'
CREATE TABLE IF NOT EXISTS rent_instalment_default
    PARTITION OF rent_instalment DEFAULT;

\echo '[Step 5] Copy old data into the new partitioned table (rows route automatically)'

INSERT INTO rent_instalment (instalment_id, tenancy_id, due_date, amount_ngn,
                             paid_at, status, created_at)
SELECT instalment_id, tenancy_id, due_date, amount_ngn,
       paid_at, status, created_at
FROM rent_instalment_old;

-- Advance the instalment_id sequence past the highest copied ID, so the
-- next INSERT does not clash.
SELECT setval(pg_get_serial_sequence('rent_instalment', 'instalment_id'),
              COALESCE((SELECT MAX(instalment_id) FROM rent_instalment), 1),
              true);

\echo '  -> old rows copied into partitioned table; sequence advanced.'
\echo ''

-- ---------------------------------------------------------------------------
-- Step 6: Recreate the FK from rent_instalment -> tenancy, and the
--         instalment_sum trigger function + trigger on the new parent.
--         In PostgreSQL 16, a trigger created on a partitioned parent is
--         automatically propagated to every existing partition AND to any
--         partition created later. So we define the trigger once on the
--         parent and it covers every session partition + the default.
-- ---------------------------------------------------------------------------
\echo '[Step 6] Recreate the FK to tenancy + the instalment_sum trigger on the parent'

ALTER TABLE rent_instalment
    ADD CONSTRAINT rent_instalment_tenancy_id_fkey
    FOREIGN KEY (tenancy_id) REFERENCES tenancy(tenancy_id);

-- The instalment_sum trigger enforces the business rule:
--   "the sum of rent_instalment.amount_ngn for a tenancy must not exceed
--    the annual rent of the room type of the room the tenancy covers."
-- The cap is resolved through: tenancy -> room -> room_type -> annual_rent_ngn.
-- NOTE: if Portfolio 1 named the annual rent column differently
--       (e.g. annual_rent instead of annual_rent_ngn), edit the SELECT below.
-- Re-use Portfolio 1's check_instalment_sum() (it locks the tenancy row and
-- compares against the tenancy's own annual rent) on the new parent table.
DROP TRIGGER IF EXISTS trg_instalment_sum ON rent_instalment;
CREATE TRIGGER trg_instalment_sum
    BEFORE INSERT OR UPDATE ON rent_instalment
    FOR EACH ROW EXECUTE FUNCTION check_instalment_sum();
\echo '  -> FK + instalment_sum trigger recreated on the partitioned parent.'
\echo ''

-- ---------------------------------------------------------------------------
-- Step 7: Recreate the secondary indexes on the partitioned parent.
--         In PG 16, CREATE INDEX on a partitioned parent automatically
--         creates matching indexes on every existing partition AND on any
--         partition created afterwards. So three statements give us
--         indexes across every session partition + the default.
-- ---------------------------------------------------------------------------
\echo '[Step 7] Recreate indexes on the partitioned parent (PG 16 propagates to partitions)'

CREATE INDEX IF NOT EXISTS rent_instalment_tenancy_id_idx
    ON rent_instalment(tenancy_id);

CREATE INDEX IF NOT EXISTS rent_instalment_due_date_idx
    ON rent_instalment(due_date);

CREATE INDEX IF NOT EXISTS rent_instalment_paid_at_idx
    ON rent_instalment(paid_at);

\echo '  -> indexes created on parent (propagated to every partition).'
\echo ''

-- ---------------------------------------------------------------------------
-- Step 8: Drop the old flat table. Its data now lives in the partitioned
--         parent and its session partitions.
-- ---------------------------------------------------------------------------
\echo '[Step 8] Drop the old flat table rent_instalment_old'

DROP TABLE rent_instalment_old;

\echo '  -> old table dropped.'
\echo ''

-- ---------------------------------------------------------------------------
-- Step 9: List every rent_instalment partition that now exists.
-- ---------------------------------------------------------------------------
\echo '[Step 9] Rows in each partition (the DEFAULT partition must show 0)'
SELECT c.relname AS partition,
       pg_get_expr(c.relpartbound, c.oid) AS holds,
       (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM %I', c.relname),
                                            false, true, '')))[1]::text::int AS instalments
  FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
 WHERE i.inhparent = 'rent_instalment'::regclass
 ORDER BY c.relname;

\echo ''
\echo '[Step 10] Partition pruning: a query for the current session reads ONE partition'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY OFF)
SELECT status, count(*), sum(amount_ngn)
  FROM rent_instalment
 WHERE due_date >= make_date(EXTRACT(YEAR FROM CURRENT_DATE - INTERVAL '8 months')::int, 9, 1)
   AND due_date <  make_date(EXTRACT(YEAR FROM CURRENT_DATE - INTERVAL '8 months')::int + 1, 9, 1)
 GROUP BY status;
\echo '  (Look for "Subplans Removed" / only one rent_instalment_s... partition scanned.)'
\echo ''
\echo '============================================================'
\echo ' partition.sql complete.'
\echo ' Next steps:'
\echo '   1. Follow replication_setup.md to build the streaming read replica.'
\echo '   2. Read cloud_architecture.md for the cloud + NDPA 2023 design.'
\echo '============================================================'
