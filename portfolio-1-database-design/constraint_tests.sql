-- =============================================================================
-- constraint_tests.sql - negative tests for CampusNest (Portfolio 1)
-- Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
-- Course  : MIT 8103 Advanced Database Systems
-- -----------------------------------------------------------------------------
-- Each test builds its OWN situation from real rows in the database (it picks
-- a real bed-space, real tenants with guarantors, year-2099 dates nobody uses),
-- tries to break ONE rule, and catches the error. It prints
--     PASS  <test>  -> blocked by <constraint name>
-- only when the error came from the constraint it was aimed at, otherwise
--     FAIL  <test>  ...
-- Everything runs inside DO blocks that are rolled back, so nothing persists.
--
-- Run:  sudo runuser -u postgres -- psql -d campusnest -f constraint_tests.sql
-- =============================================================================
\set ON_ERROR_STOP 1
\pset footer off
\echo '============================================================'
\echo ' CampusNest Portfolio 1 - constraint tests (each one should PASS)'
\echo '============================================================'

CREATE TEMP TABLE test_result (n INT, test TEXT, result TEXT, detail TEXT);

-- Helper: picks two real tenants (with guarantors) and two real bed-spaces.
CREATE TEMP TABLE pick AS
SELECT (SELECT room_id FROM room ORDER BY room_id LIMIT 1)                 AS room_a,
       (SELECT room_id FROM room ORDER BY room_id OFFSET 1 LIMIT 1)        AS room_b,
       (SELECT tenant_id FROM guarantor ORDER BY tenant_id LIMIT 1)        AS tenant_a,
       (SELECT tenant_id FROM guarantor ORDER BY tenant_id OFFSET 1 LIMIT 1) AS tenant_b,
       (SELECT room_type_id FROM room_type ORDER BY room_type_id LIMIT 1)  AS rt;

-- Runs one attempt and records PASS only if the expected constraint fired.
CREATE OR REPLACE FUNCTION pg_temp.expect_block(p_n INT, p_test TEXT, p_sql TEXT, p_constraint TEXT)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_con TEXT; v_msg TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        INSERT INTO test_result VALUES (p_n, p_test, 'FAIL', 'statement was NOT blocked');
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_con = CONSTRAINT_NAME, v_msg = MESSAGE_TEXT;
        IF v_con = p_constraint OR v_msg LIKE '%' || p_constraint || '%' THEN
            INSERT INTO test_result VALUES (p_n, p_test, 'PASS', 'blocked by ' || p_constraint || ': ' || v_msg);
        ELSE
            INSERT INTO test_result VALUES (p_n, p_test, 'FAIL', 'wrong error: ' || v_msg);
        END IF;
    END;   -- the inner block's work is rolled back by the exception
END $$;

\o /dev/null
SELECT pg_temp.expect_block(1, 'Two overlapping tenancies on one bed-space',
  format($q$INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn) VALUES
            (%s, %s, '2099-09-01', '2100-09-01', 500000),
            (%s, %s, '2100-01-01', '2101-01-01', 500000)$q$, room_a, tenant_a, room_a, tenant_b),
  'tenancy_no_room_overlap') FROM pick;

SELECT pg_temp.expect_block(2, 'One tenant in two bed-spaces at the same time',
  format($q$INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn) VALUES
            (%s, %s, '2099-09-01', '2100-09-01', 500000),
            (%s, %s, '2100-01-01', '2101-01-01', 500000)$q$, room_a, tenant_a, room_b, tenant_a),
  'tenancy_no_tenant_overlap') FROM pick;

CREATE OR REPLACE FUNCTION pg_temp.t3_overpay() RETURNS void LANGUAGE plpgsql AS $$
DECLARE p RECORD; v_id BIGINT;
BEGIN
    SELECT * INTO p FROM pick;
    INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn)
    VALUES (p.room_a, p.tenant_a, '2099-09-01', '2100-09-01', 500000) RETURNING tenancy_id INTO v_id;
    INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn) VALUES (v_id, '2099-09-01', 400000); -- ok
    INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn) VALUES (v_id, '2100-03-01', 200000); -- 600k > 500k
END $$;
SELECT pg_temp.expect_block(3, 'Instalments adding up to more than the annual rent',
  'SELECT pg_temp.t3_overpay()', 'exceed annual rent');

SELECT pg_temp.expect_block(4, 'Duplicate waitlist position for one room type',
  format($q$INSERT INTO waitlist_entry (room_type_id, tenant_id, position) VALUES (%s, %s, 9999), (%s, %s, 9999)$q$,
         rt, tenant_a, rt, tenant_b),
  'waitlist_entry_room_type_id_position_key') FROM pick;

SELECT pg_temp.expect_block(5, 'Annual rent of zero',
  format($q$INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn)
            VALUES (%s, %s, '2099-09-01', '2100-09-01', 0)$q$, room_a, tenant_a),
  'tenancy_annual_rent_ngn_check') FROM pick;

SELECT pg_temp.expect_block(6, 'Tenancy ending on the day it starts',
  format($q$INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn)
            VALUES (%s, %s, '2099-09-01', '2099-09-01', 500000)$q$, room_a, tenant_a),
  'tenancy_check') FROM pick;

SELECT pg_temp.expect_block(7, 'Room type that is not single/shared_2/shared_4',
  $q$INSERT INTO room_type (lodge_id, name, annual_rent_ngn, capacity)
     SELECT lodge_id, 'shared_6', 200000, 4 FROM lodge ORDER BY lodge_id LIMIT 1$q$,
  'room_type_name_check');

DO $$
DECLARE p RECORD; v_ok BOOLEAN := false; v_err TEXT;
BEGIN
    SELECT * INTO p FROM pick;
    BEGIN
        INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn, status)
        VALUES (p.room_a, p.tenant_a, '2099-09-01', '2100-09-01', 500000, 'cancelled'),
               (p.room_a, p.tenant_b, '2099-09-01', '2100-09-01', 500000, 'active');
        v_ok := true;
        RAISE EXCEPTION 'undo';           -- roll the two test rows back
    EXCEPTION WHEN raise_exception THEN NULL;
              WHEN OTHERS THEN v_err := SQLERRM;
    END;
    INSERT INTO test_result VALUES (8, 'Cancelled booking frees the bed-space (allowed)',
        CASE WHEN v_ok THEN 'PASS' ELSE 'FAIL' END,
        CASE WHEN v_ok THEN 'allowed: a cancelled and an active tenancy on the same bed and dates'
             ELSE 'wrongly blocked: ' || v_err END);
END $$;

\o
-- Test 9 must COMMIT to reach the deferred trigger, so it runs on its own.
\echo ''
\echo '--- Test 9: tenant with no guarantor (deferred trigger fires at COMMIT) ---'
\set ON_ERROR_STOP 0
BEGIN;
INSERT INTO tenant (full_name, email, phone, student_matric, nearest_school)
VALUES ('Test NoGuarantor', 'test.noguarantor@example.ng', '+234 800 000 0000', 'UNILAG/26/00000', 'UNILAG');
COMMIT;
\set ON_ERROR_STOP 1
INSERT INTO test_result
SELECT 9, 'Tenant with no guarantor (checked at COMMIT)',
       CASE WHEN count(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
       CASE WHEN count(*) = 0 THEN 'blocked by trg_require_guarantor: the COMMIT above failed, row not saved'
            ELSE 'tenant without guarantor was saved' END
  FROM tenant WHERE email = 'test.noguarantor@example.ng';

\echo ''
SELECT n AS "#", result, test, detail FROM test_result ORDER BY n;
SELECT count(*) FILTER (WHERE result = 'PASS') || ' of ' || count(*) || ' constraint tests passed' AS summary
  FROM test_result;
