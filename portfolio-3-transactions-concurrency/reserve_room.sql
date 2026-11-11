-- =============================================================================
-- reserve_room.sql
-- Portfolio 3 - Transactions and Concurrency
-- Student : Amaka Benedicta Chukwudebe
-- Matric  : 2026/A/MIT/0517
-- Course  : MIT 8103 Advanced Database Systems, Miva Open University
-- Case    : CampusNest - Private Student Accommodation Booking
-- =============================================================================
--
-- reserve_room(p_tenant_id, p_room_type_id, [p_session_start], [p_first_instalment_ngn])
--
-- Runs INSIDE the caller's transaction (it never COMMITs itself), so the
-- caller decides: COMMIT when the payment succeeds, ROLLBACK when it fails.
--
-- How it stays correct when many students book at the same moment
-- ----------------------------------------------------------------
-- 1. EXCLUSION CONSTRAINT (the main defence, from Portfolio 1):
--      tenancy_no_room_overlap  EXCLUDE USING gist (room_id WITH =,
--                                daterange(start_date,end_date) WITH &&)
--    Whatever the application does, the database itself refuses a second
--    overlapping tenancy on the same bed-space. Two students can never hold
--    the same bed for the same session.
-- 2. FOR UPDATE SKIP LOCKED when choosing a bed:
--    the first caller locks the bed it picked; a second caller at the same
--    moment SKIPS that locked bed and takes the next free one, instead of
--    waiting and then hitting the exclusion constraint. Result: both
--    students get different beds and nobody waits.
-- 3. Waitlist positions: the room_type row is locked (FOR UPDATE) before
--    MAX(position)+1 is computed, so two students joining the same queue
--    at the same moment get positions n and n+1, never a duplicate.
-- 4. If the exclusion constraint does fire (e.g. the tenant already holds an
--    overlapping tenancy), the function returns outcome = 'conflict' with
--    the constraint name, instead of hiding every error as before.
-- =============================================================================

-- Start date of the NEXT academic session (sessions run 1 Sept -> 1 Sept).
CREATE OR REPLACE FUNCTION next_session_start() RETURNS DATE
LANGUAGE sql STABLE AS $$
    SELECT make_date(EXTRACT(YEAR FROM CURRENT_DATE)::int
                     + CASE WHEN EXTRACT(MONTH FROM CURRENT_DATE) >= 9 THEN 1 ELSE 0 END, 9, 1);
$$;

DROP FUNCTION IF EXISTS reserve_room(BIGINT, BIGINT, DATE, NUMERIC);

CREATE OR REPLACE FUNCTION reserve_room(
    p_tenant_id            BIGINT,
    p_room_type_id         BIGINT,
    p_session_start        DATE DEFAULT NULL,
    p_first_instalment_ngn NUMERIC(12,2) DEFAULT NULL
) RETURNS TABLE (
    outcome           TEXT,
    tenancy_id        BIGINT,
    room_code         TEXT,
    waitlist_position INT,
    message           TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_start    DATE := COALESCE(p_session_start, next_session_start());
    v_session_end      DATE;
    v_annual_rent      NUMERIC(12,2);
    v_room_id          BIGINT;
    v_room_code        TEXT;
    v_new_tenancy_id   BIGINT;
    v_new_position     INT;
    v_constraint       TEXT;
BEGIN
    v_session_end := (v_session_start + interval '12 months')::DATE;

    SELECT rt.annual_rent_ngn INTO v_annual_rent
      FROM room_type rt WHERE rt.room_type_id = p_room_type_id;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'error'::TEXT, NULL::BIGINT, NULL::TEXT, NULL::INT,
                            ('Room type ' || p_room_type_id || ' does not exist')::TEXT;
        RETURN;
    END IF;

    -- Pick one free bed of this type; skip beds another session has locked.
    SELECT r.room_id, r.room_code INTO v_room_id, v_room_code
      FROM room r
     WHERE r.room_type_id = p_room_type_id
       AND NOT EXISTS (SELECT 1 FROM tenancy t
                        WHERE t.room_id = r.room_id
                          AND t.status <> 'cancelled'
                          AND daterange(t.start_date, t.end_date)
                              && daterange(v_session_start, v_session_end))
     ORDER BY r.room_id
     LIMIT 1
       FOR UPDATE OF r SKIP LOCKED;

    IF v_room_id IS NOT NULL THEN
        BEGIN
            INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn, status)
            VALUES (v_room_id, p_tenant_id, v_session_start, v_session_end, v_annual_rent, 'active')
            RETURNING tenancy.tenancy_id INTO v_new_tenancy_id;
        EXCEPTION WHEN exclusion_violation THEN
            GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
            RETURN QUERY SELECT 'conflict'::TEXT, NULL::BIGINT, v_room_code, NULL::INT,
                                ('Blocked by ' || v_constraint)::TEXT;
            RETURN;
        END;

        INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, paid_at, status)
        VALUES (v_new_tenancy_id, v_session_start,
                COALESCE(p_first_instalment_ngn, v_annual_rent), now(), 'paid');

        RETURN QUERY SELECT 'reserved'::TEXT, v_new_tenancy_id, v_room_code, NULL::INT,
               ('Bed ' || v_room_code || ' reserved for tenant ' || p_tenant_id
                || ' for ' || v_session_start || ' to ' || v_session_end)::TEXT;
        RETURN;
    END IF;

    -- No free bed: join the waitlist. Lock the room_type row first so two
    -- students joining at once cannot compute the same MAX(position)+1.
    PERFORM 1 FROM room_type WHERE room_type.room_type_id = p_room_type_id FOR UPDATE;
    INSERT INTO waitlist_entry (room_type_id, tenant_id, position)
    SELECT p_room_type_id, p_tenant_id, COALESCE(MAX(w.position), 0) + 1
      FROM waitlist_entry w WHERE w.room_type_id = p_room_type_id
    RETURNING waitlist_entry.position INTO v_new_position;

    RETURN QUERY SELECT 'waitlisted'::TEXT, NULL::BIGINT, NULL::TEXT, v_new_position,
           ('No free bed of room type ' || p_room_type_id || ' for ' || v_session_start
            || '; tenant ' || p_tenant_id || ' is number ' || v_new_position || ' on the waitlist')::TEXT;
END;
$$;

COMMENT ON FUNCTION reserve_room(BIGINT, BIGINT, DATE, NUMERIC) IS
'CampusNest P3: reserve a free bed of a room type for the next academic session (or a given start),
recording the first instalment as paid; else join the waitlist. Exclusion constraint + SKIP LOCKED +
room_type lock keep it correct under concurrency. The caller COMMITs or ROLLs BACK.';

\echo 'reserve_room() and next_session_start() loaded.'
SELECT next_session_start() AS next_session_starts;
