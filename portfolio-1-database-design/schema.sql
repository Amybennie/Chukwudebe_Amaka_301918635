-- =============================================================================
-- schema.sql - CampusNest relational schema (Portfolio 1)
-- -----------------------------------------------------------------------------
-- Student : Amaka Benedicta Chukwudebe
-- Matric  : 2026/A/MIT/0517
-- Course  : MIT 8103 Advanced Database Systems, Miva Open University
-- Session : 2026/2027 First Semester (September Cohort 2026)
-- Study   : Study Session 1 - Review of Traditional Relational Databases
--           and Advanced Concepts (normalisation, design, advanced constraints)
-- -----------------------------------------------------------------------------
-- This file drops and recreates the public schema, creates the btree_gist and
-- pgcrypto extensions, defines 9 tables in dependency order, adds the
-- exclusion / check / unique constraints, helpful indexes, and the two
-- trigger functions that enforce business rules:
--   * rent_instalment rows for one tenancy must not sum above annual_rent_ngn
--   * every tenant must have at least one guarantor (deferred constraint trigger)
--
-- Run with:
--   sudo runuser -u postgres -- psql -d campusnest -v ON_ERROR_STOP=1 -f schema.sql
--
-- Currency: Naira (NGN). All amount columns are NUMERIC(12,2).
--   Example: 850000.00 = 850,000 naira (NGN 850,000).
--   The unicode naira sign is NOT used inside .sql files.
-- =============================================================================

-- 0. Start clean. Drop and recreate the public schema so the script is
--    re-runnable from a known state.
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- 1. Extensions.
--    btree_gist : required for EXCLUDE USING gist on
--                 (room_id WITH =, daterange WITH &&). Without it we cannot
--                 express "no overlapping tenancies on the same room".
--    pgcrypto   : provides gen_random_uuid() if any later portfolio needs it.
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Tables in dependency order.
--    lodge -> room_type -> room -> tenant -> guarantor -> tenancy ->
--    rent_instalment -> waitlist_entry -> maintenance_ticket

-- 2.1 lodge - a physical student lodge near one of the four schools.
CREATE TABLE lodge (
    lodge_id       BIGSERIAL PRIMARY KEY,
    name           TEXT        NOT NULL,
    nearest_school TEXT        NOT NULL CHECK (nearest_school IN ('UNILAG','YABATECH','LASU','UNN')),
    address_line   TEXT,
    city           TEXT,
    state          TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.2 room_type - the booking unit (single, shared_2, shared_4) and the
--     annual rent per bed in Naira. UNIQUE(lodge_id, name) means each lodge
--     offers at most one of each type.
CREATE TABLE room_type (
    room_type_id    BIGSERIAL   PRIMARY KEY,
    lodge_id        BIGINT      NOT NULL REFERENCES lodge(lodge_id) ON DELETE CASCADE,
    name            TEXT        NOT NULL CHECK (name IN ('single','shared_2','shared_4')),
    annual_rent_ngn NUMERIC(12,2) NOT NULL CHECK (annual_rent_ngn > 0),
    capacity        INT         NOT NULL CHECK (capacity BETWEEN 1 AND 4),
    UNIQUE (lodge_id, name)
);

-- 2.3 room - a physical room inside a lodge, of a given room_type.
CREATE TABLE room (
    room_id      BIGSERIAL   PRIMARY KEY,
    lodge_id     BIGINT      NOT NULL REFERENCES lodge(lodge_id)    ON DELETE CASCADE,
    room_type_id BIGINT      NOT NULL REFERENCES room_type(room_type_id) ON DELETE CASCADE,
    room_code    TEXT        NOT NULL,
    floor        INT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (lodge_id, room_code)
);

-- 2.4 tenant - a student who may hold a tenancy and/or join a waitlist.
CREATE TABLE tenant (
    tenant_id      BIGSERIAL   PRIMARY KEY,
    full_name      TEXT        NOT NULL,
    email          TEXT        UNIQUE,
    phone          TEXT,
    student_matric TEXT,
    nearest_school TEXT        CHECK (nearest_school IN ('UNILAG','YABATECH','LASU','UNN')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.5 guarantor - one guarantor per tenant (UNIQUE on tenant_id). The deferred
--     constraint trigger below enforces that every tenant has at least one.
CREATE TABLE guarantor (
    guarantor_id  BIGSERIAL   PRIMARY KEY,
    tenant_id     BIGINT      NOT NULL UNIQUE REFERENCES tenant(tenant_id) ON DELETE CASCADE,
    full_name     TEXT        NOT NULL,
    phone         TEXT,
    email         TEXT,
    relationship  TEXT,
    home_address  TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.6 tenancy - a tenant renting a room for [start_date, end_date).
--     annual_rent_ngn is a historical snapshot of room_type.annual_rent_ngn
--     at booking time (deliberate denormalisation - see notes_3nf.md).
CREATE TABLE tenancy (
    tenancy_id      BIGSERIAL   PRIMARY KEY,
    room_id         BIGINT      NOT NULL REFERENCES room(room_id)   ON DELETE CASCADE,
    tenant_id       BIGINT      NOT NULL REFERENCES tenant(tenant_id) ON DELETE CASCADE,
    start_date      DATE        NOT NULL,
    end_date        DATE        NOT NULL,
    annual_rent_ngn NUMERIC(12,2) NOT NULL CHECK (annual_rent_ngn > 0),
    status          TEXT        NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active','ended','cancelled')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_date > start_date)
);

-- 2.7 rent_instalment - a scheduled payment for a tenancy. The sum of
--     amount_ngn for one tenancy must not exceed tenancy.annual_rent_ngn
--     (enforced by the trg_instalment_sum trigger below).
CREATE TABLE rent_instalment (
    instalment_id BIGSERIAL   PRIMARY KEY,
    tenancy_id    BIGINT      NOT NULL REFERENCES tenancy(tenancy_id) ON DELETE CASCADE,
    due_date      DATE        NOT NULL,
    amount_ngn    NUMERIC(12,2) NOT NULL CHECK (amount_ngn > 0),
    paid_at       TIMESTAMPTZ,
    status        TEXT        NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('pending','paid','overdue')),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2.8 waitlist_entry - a tenant queuing for a sold-out room_type.
--     position is unique per room_type, and a tenant can appear at most
--     once per room_type.
CREATE TABLE waitlist_entry (
    waitlist_id  BIGSERIAL   PRIMARY KEY,
    room_type_id BIGINT      NOT NULL REFERENCES room_type(room_type_id) ON DELETE CASCADE,
    tenant_id    BIGINT      NOT NULL REFERENCES tenant(tenant_id)      ON DELETE CASCADE,
    position     INT         NOT NULL CHECK (position > 0),
    joined_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (room_type_id, position),
    UNIQUE (room_type_id, tenant_id)
);

-- 2.9 maintenance_ticket - relational stub for Portfolio 1.
--     Portfolio 4 replaces this with a richer MongoDB document version.
--     room_id and tenant_id are nullable because a ticket may concern a
--     common area (no room) or be logged by a lodge manager (no tenant).
CREATE TABLE maintenance_ticket (
    ticket_id   BIGSERIAL   PRIMARY KEY,
    lodge_id    BIGINT      NOT NULL REFERENCES lodge(lodge_id) ON DELETE CASCADE,
    room_id     BIGINT      REFERENCES room(room_id)   ON DELETE SET NULL,
    tenant_id   BIGINT      REFERENCES tenant(tenant_id) ON DELETE SET NULL,
    category    TEXT        NOT NULL CHECK (category IN ('plumbing','electrical','furniture','pest_control','other')),
    reported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,
    status      TEXT        NOT NULL DEFAULT 'open'
                       CHECK (status IN ('open','in_progress','resolved','closed')),
    summary     TEXT        NOT NULL
);

-- 3. Exclusion constraints - the heart of Portfolio 1.
--    The index method is GiST; the btree_gist extension is what lets GiST
--    handle the plain "=" on a BIGINT id. These combine an equality (=) on an id column with
--    an overlap (&&) on a daterange, which plain btree indexes cannot do.

-- 3a. No two overlapping tenancies on the same room.
ALTER TABLE tenancy
    ADD CONSTRAINT tenancy_no_room_overlap
    EXCLUDE USING gist (
        room_id WITH =,
        daterange(start_date, end_date) WITH &&
    ) WHERE (status <> 'cancelled');   -- a cancelled booking frees the room

-- 3b. A tenant cannot hold two overlapping tenancies (even on different rooms).
ALTER TABLE tenancy
    ADD CONSTRAINT tenancy_no_tenant_overlap
    EXCLUDE USING gist (
        tenant_id WITH =,
        daterange(start_date, end_date) WITH &&
    ) WHERE (status <> 'cancelled');

-- 4. Helpful indexes. Foreign keys are NOT auto-indexed in PostgreSQL, so we
--    add indexes on every FK column that appears in a join, a trigger, or a
--    filter. The exclusion constraints above already create GiST indexes on
--    tenancy(room_id) and tenancy(tenant_id), so we do not re-add btree ones.
CREATE INDEX idx_tenancy_tenant          ON tenancy(tenant_id);
CREATE INDEX idx_tenancy_room            ON tenancy(room_id);
CREATE INDEX idx_instalment_tenancy_due  ON rent_instalment(tenancy_id, due_date);
CREATE INDEX idx_waitlist_rt_pos         ON waitlist_entry(room_type_id, position);
CREATE INDEX idx_maint_lodge_status      ON maintenance_ticket(lodge_id, status);
CREATE INDEX idx_guarantor_tenant        ON guarantor(tenant_id);
CREATE INDEX idx_room_lodge_code         ON room(lodge_id, room_code);
CREATE INDEX idx_room_type_lodge         ON room_type(lodge_id);

-- 5. Trigger functions.

-- 5a. Instalments for a tenancy must sum to no more than the annual rent.
--     Fires BEFORE INSERT OR UPDATE on rent_instalment, per row. The function
--     reads the tenancy's annual_rent_ngn and the current sum of instalments
--     for that tenancy, and raises if adding NEW.amount_ngn would overshoot.
CREATE OR REPLACE FUNCTION check_instalment_sum() RETURNS trigger AS $$
DECLARE
    total_so_far NUMERIC(12,2);
    annual_rent  NUMERIC(12,2);
BEGIN
    -- FOR UPDATE locks the parent tenancy, so two sessions adding
    -- instalments to the same tenancy at once are checked one after the other.
    SELECT annual_rent_ngn INTO annual_rent
      FROM tenancy
     WHERE tenancy_id = NEW.tenancy_id
       FOR UPDATE;

    SELECT COALESCE(SUM(amount_ngn), 0) INTO total_so_far
      FROM rent_instalment
     WHERE tenancy_id = NEW.tenancy_id
       -- on UPDATE, do not count the row being updated twice
       AND (TG_OP = 'INSERT' OR instalment_id <> NEW.instalment_id);

    IF total_so_far + NEW.amount_ngn > annual_rent THEN
        RAISE EXCEPTION 'Instalments (%) + new (%) exceed annual rent (%) for tenancy %',
            total_so_far, NEW.amount_ngn, annual_rent, NEW.tenancy_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_instalment_sum
    BEFORE INSERT OR UPDATE ON rent_instalment
    FOR EACH ROW EXECUTE FUNCTION check_instalment_sum();

-- 5b. Every tenant needs at least one guarantor. This is a DEFERRABLE
--     INITIALLY DEFERRED CONSTRAINT TRIGGER so that a tenant and its
--     guarantor can be inserted in either order inside the same transaction;
--     the check only fires at COMMIT.
CREATE OR REPLACE FUNCTION require_guarantor() RETURNS trigger AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM guarantor WHERE tenant_id = NEW.tenant_id) THEN
        RAISE EXCEPTION 'Tenant % has no guarantor', NEW.tenant_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER trg_require_guarantor
    AFTER INSERT ON tenant
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION require_guarantor();

-- Done. The schema is ready for seed.sql and bulk_generator.py.
