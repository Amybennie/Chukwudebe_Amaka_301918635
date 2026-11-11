-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2
-- Query Processing and Optimisation
-- Student : Amaka Benedicta Chukwudebe  (2026/A/MIT/0517)
-- Case    : CampusNest - Private Student Accommodation Booking
-- File    : indexes.sql
-- Purpose : Create the indexes that target the slow operations found
--           in the BEFORE EXPLAIN plans. Run this script BETWEEN
--           explain_before.sql and explain_after.sql.
--
-- Design notes:
--   * PostgreSQL automatically creates B-tree indexes for PRIMARY KEY
--     and UNIQUE constraints, so the columns already covered by those
--     (every PK column, room_type(lodge_id,name), room(lodge_id,room_code),
--      tenant.email, waitlist_entry(room_type_id,position),
--      waitlist_entry(room_type_id,tenant_id)) are NOT re-indexed here.
--   * PostgreSQL does NOT auto-create indexes on FOREIGN KEY columns.
--     Most of the indexes below fill in exactly those FK-side columns.
--   * Two of the indexes are PARTIAL indexes (WHERE paid_at IS NULL and
--     WHERE resolved_at IS NOT NULL). These match the predicates in
--     Q4 and Q6 so the planner can seek directly to the relevant rows.
--   * CREATE INDEX IF NOT EXISTS makes this script idempotent: running
--     it twice does not error and does not duplicate work.
--   * PostgreSQL runs an automatic ANALYZE on the affected table after
--     each CREATE INDEX, so the AFTER EXPLAIN plans in explain_after.sql
--     see fresh planner statistics without a separate ANALYZE step.
-- =====================================================================

\echo ===================================================================
\echo MIT 8103 Advanced Database Systems - Portfolio 2
\echo Index creation script
\echo Run AFTER explain_before.sql and BEFORE explain_after.sql.
\echo ===================================================================
\echo

-- ---------------------------------------------------------------------
-- Q1 / Q2 helper: room.lodge_id
--   The 'rooms of a given lodge' lookup (Q1 WHERE l.name = ... and the
--   Q2 LEFT JOIN room) currently Seq Scans room because the FK column
--   lodge_id has no index. This B-tree lets the planner seek straight
--   to the rooms of one lodge.
-- ---------------------------------------------------------------------
\echo -- Q1/Q2 helper: room.lodge_id (foreign-key side, not auto-indexed)
CREATE INDEX IF NOT EXISTS idx_room_lodge_id
    ON room (lodge_id);

-- ---------------------------------------------------------------------
-- Q1 helper: room.room_type_id
--   The join room -> room_type uses room_type_id on the room side.
--   Indexing it lets the planner use a nested-loop join driven by
--   room_type rows when that side is smaller.
-- ---------------------------------------------------------------------
\echo -- Q1 helper: room.room_type_id (foreign-key side, not auto-indexed)
CREATE INDEX IF NOT EXISTS idx_room_room_type_id
    ON room (room_type_id);

-- ---------------------------------------------------------------------
-- Q1 helper: tenancy.room_id
--   The NOT EXISTS overlap subquery in Q1 is correlated on
--   t.room_id = r.room_id. Without an index here, the planner Seq
--   Scans tenancy once per candidate room. This index lets it seek
--   only the tenancies of that one room.
-- ---------------------------------------------------------------------
\echo -- Q1 helper: tenancy.room_id (drives the NOT EXISTS overlap lookup)
CREATE INDEX IF NOT EXISTS idx_tenancy_room_id
    ON tenancy (room_id);

-- ---------------------------------------------------------------------
-- Q4 helper: tenancy.tenant_id
--   The join tenancy -> tenant in Q4 (and the same join in any tenant
--   report) is on tenant_id; the FK column has no auto-index.
-- ---------------------------------------------------------------------
\echo -- Q4 helper: tenancy.tenant_id (foreign-key side, not auto-indexed)
CREATE INDEX IF NOT EXISTS idx_tenancy_tenant_id
    ON tenancy (tenant_id);

-- ---------------------------------------------------------------------
-- Q1 helper: tenancy(start_date, end_date)
--   A composite B-tree on the date columns lets the planner range-seek
--   the tenancies that could overlap a given session window, instead of
--   filtering all of them. Combined with idx_tenancy_room_id above,
--   the planner can pick whichever access path has the lower cost.
-- ---------------------------------------------------------------------
\echo -- Q1 helper: tenancy(start_date, end_date) for daterange overlap
CREATE INDEX IF NOT EXISTS idx_tenancy_start_end
    ON tenancy (start_date, end_date);

-- ---------------------------------------------------------------------
-- Q3 / Q4 helper: rent_instalment.tenancy_id
--   Both the collected-vs-outstanding sum (Q3) and the overdue join
--   (Q4) walk through tenancy -> rent_instalment. Indexing the FK
--   column tenancy_id lets the planner use an index-nested-loop from
--   tenancy into rent_instalment instead of a hash of the whole table.
-- ---------------------------------------------------------------------
\echo -- Q3/Q4 helper: rent_instalment.tenancy_id (foreign-key side)
CREATE INDEX IF NOT EXISTS idx_rent_instalment_tenancy_id
    ON rent_instalment (tenancy_id);

-- ---------------------------------------------------------------------
-- Q4 helper: rent_instalment(due_date) WHERE paid_at IS NULL  [PARTIAL]
--   This is the headline optimisation for Q4. The query predicate is
--   due_date < CURRENT_DATE AND paid_at IS NULL. The partial index
--   stores ONLY the unpaid instalments, ordered by due_date. The
--   planner can use this index to go straight to overdue rows by
--   range, then walk the index forward.
--   Note: a partial index is smaller than a full index and stays small
--   as instalments get paid (their rows are removed from the index).
-- ---------------------------------------------------------------------
\echo -- Q4 helper: rent_instalment(due_date) WHERE paid_at IS NULL  (PARTIAL)
CREATE INDEX IF NOT EXISTS idx_rent_instalment_overdue
    ON rent_instalment (due_date)
    WHERE paid_at IS NULL;

-- ---------------------------------------------------------------------
-- Q3 helper: rent_instalment.paid_at
--   Q3 splits instalments into paid (paid_at IS NOT NULL) and unpaid
--   (paid_at IS NULL) with FILTER clauses. Indexing paid_at lets the
--   planner consider an index-only scan or bitmap for the paid side,
--   and pairs with the partial index above for the unpaid side.
-- ---------------------------------------------------------------------
\echo -- Q3 helper: rent_instalment.paid_at (supports the FILTER split)
CREATE INDEX IF NOT EXISTS idx_rent_instalment_paid_at
    ON rent_instalment (paid_at);

-- ---------------------------------------------------------------------
-- Q5 helper: waitlist_entry.room_type_id
--   The waitlist-count query groups by room_type_id and joins
--   waitlist_entry to room_type. The FK column room_type_id has no
--   auto-index (the UNIQUE constraints cover the composite
--   (room_type_id, position) and (room_type_id, tenant_id) only).
--   A standalone index on room_type_id supports the LEFT JOIN.
-- ---------------------------------------------------------------------
\echo -- Q5 helper: waitlist_entry.room_type_id (foreign-key side)
CREATE INDEX IF NOT EXISTS idx_waitlist_room_type_id
    ON waitlist_entry (room_type_id);

-- ---------------------------------------------------------------------
-- Q6 helper: maintenance_ticket(lodge_id) WHERE resolved_at IS NOT NULL
--   [PARTIAL]  The avg-resolution query in Q6 only cares about tickets
--   that have actually been resolved. The partial index holds only
--   those rows, organised by lodge_id, so the planner can compute the
--   per-lodge count and AVG by walking a small index segment.
-- ---------------------------------------------------------------------
\echo -- Q6 helper: maintenance_ticket(lodge_id) WHERE resolved_at IS NOT NULL  (PARTIAL)
CREATE INDEX IF NOT EXISTS idx_maintenance_lodge_resolved
    ON maintenance_ticket (lodge_id)
    WHERE resolved_at IS NOT NULL;

-- ---------------------------------------------------------------------
-- Q6 helper: maintenance_ticket.resolved_at
--   Supports the resolved_at IS NOT NULL filter in Q6 and any future
--   'how quickly are we closing tickets?' query that filters on the
--   resolution timestamp.
-- ---------------------------------------------------------------------
\echo -- Q6 helper: maintenance_ticket.resolved_at (supports resolved_at IS NOT NULL)
CREATE INDEX IF NOT EXISTS idx_maintenance_resolved_at
    ON maintenance_ticket (resolved_at);

\echo
\echo ===================================================================
\echo All Portfolio 2 indexes created (or already existed).
\echo PostgreSQL automatically ANALYZEd each affected table, so the
\echo planner now has fresh statistics.
\echo Next: run explain_after.sql and compare the plans.
\echo ===================================================================

-- Q7: front-desk lookup of one student by matric number. Without this the
-- planner must read all ~36,000 tenant rows to find one student.
CREATE INDEX IF NOT EXISTS idx_tenant_matric
    ON tenant (student_matric);

-- Refresh statistics so the planner knows about the new indexes.
ANALYZE;
