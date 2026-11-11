-- =============================================================================
-- isolation_levels.sql
-- Portfolio 3 - Transactions and Concurrency
-- Student : Amaka Benedicta Chukwudebe
-- Matric  : 2026/A/MIT/0517
-- Course  : MIT 8103 Advanced Database Systems, Miva Open University
-- Case    : CampusNest - Private Student Accommodation Booking
-- =============================================================================
--
-- What this file demonstrates
-- ---------------------------
--   PostgreSQL's three isolation levels, in two terminals, on the CampusNest
--   tenancy table:
--
--     DEMO 1 - READ COMMITTED (the default):
--         Terminal 1 reads count(*) FROM tenancy. Terminal 2 inserts a new
--         tenancy and commits. Terminal 1 reads count(*) AGAIN and sees the
--         new row, because each statement in READ COMMITTED sees the latest
--         committed data.
--
--     DEMO 2 - REPEATABLE READ:
--         Terminal 1 begins a REPEATABLE READ transaction and reads count(*).
--         Terminal 2 inserts a new tenancy and commits. Terminal 1 reads
--         count(*) AGAIN and sees the SAME count as before, because the
--         transaction's snapshot was fixed at BEGIN time.
--
--     DEMO 3 - SERIALIZABLE:
--         Terminal 1 begins a SERIALIZABLE transaction and reads sum(...) of
--         rent. Terminal 2 inserts a new tenancy + instalment and commits.
--         Terminal 1 then tries to INSERT a new row that depends on the read
--         and commits. PostgreSQL's Serializable Snapshot Isolation (SSI)
--         detects the conflict and aborts Terminal 1's transaction with
--         ERROR: could not serialize access due to read/write dependencies
--         among transactions (SQLSTATE 40001, serialization_failure).
--
-- How to run this file
-- --------------------
--   1. Open TWO Codespaces terminals.
--   2. In BOTH terminals, connect to campusnest via the Unix socket:
--          sudo runuser -u postgres -- psql -d campusnest
--   3. In TERMINAL 1, run this file:
--          \i isolation_levels.sql
--      (or, from the shell:  sudo runuser -u postgres -- psql -d campusnest -f isolation_levels.sql)
--   4. Whenever Terminal 1 pauses with a "Press Enter ..." prompt, switch to
--      Terminal 2 and run the SQL that the script echoes, then come back to
--      Terminal 1 and press Enter.
--
--   All SQL executed by this file runs in Terminal 1 only. The Terminal 2 SQL
--   is shown to you via \echo lines for you to copy-paste into Terminal 2.
--
--   ON_ERROR_STOP is set off inside this file so that the expected
--   serialization_failure in DEMO 3 does not abort the script.
-- =============================================================================

\set ON_ERROR_STOP off
\pset pager off
\pset format aligned

\echo ''
\echo '======================================================================'
\echo ' Isolation Levels Demo - MIT 8103 Portfolio 3'
\echo ' Student: Amaka Benedicta Chukwudebe (2026/A/MIT/0517)'
\echo '======================================================================'
\echo ''
\echo ' This script runs in TERMINAL 1.'
\echo ' Open a SECOND terminal alongside this one and connect with:'
\echo '     sudo runuser -u postgres -- psql -d campusnest'
\echo ''
\echo ' Whenever the script pauses with "Press Enter ...", switch to Terminal 2,'
\echo ' run the SQL shown, then come back and press Enter.'
\echo ''

-- ---------------------------------------------------------------------------
-- Setup: pick a session window far enough in the future that no Portfolio 1
-- seed tenancy overlaps it. We use the first day of the month 37 months from
-- today through the same day 49 months from today (a 12-month window).
-- This guarantees every room is "free" for our demo, so T2's INSERTs never
-- collide with existing data or with the exclusion constraint.
-- ---------------------------------------------------------------------------
SELECT (date_trunc('month', now()) + interval '37 months')::date  AS demo_start,
       (date_trunc('month', now()) + interval '49 months')::date  AS demo_end,
       now()                                                       AS script_start
\gset

\echo 'Session window for all three demos:'
\echo '  demo_start   =' :demo_start
\echo '  demo_end     =' :demo_end
\echo ''

-- Pick a test tenant that T2 will use for all three demo inserts.
SELECT tenant_id AS t2_tenant_id, full_name AS t2_tenant_name
  FROM tenant
 ORDER BY tenant_id
 LIMIT 1
\gset

\echo 'Terminal 2 will insert tenancies for this test tenant:'
\echo '  t2_tenant_id   =' :t2_tenant_id
\echo '  t2_tenant_name =' :t2_tenant_name
\echo ''

-- Pick three free rooms for T2's three inserts (one per demo).
-- We use room_id > previous to get distinct rooms.
SELECT r.room_id AS t2_room_1
  FROM room r
 WHERE NOT EXISTS (
       SELECT 1 FROM tenancy t
        WHERE t.room_id = r.room_id
          AND t.status <> 'cancelled'
          AND daterange(t.start_date, t.end_date)
              && daterange(:'demo_start'::date, :'demo_end'::date)
       )
 ORDER BY r.room_id
 LIMIT 1
\gset

SELECT r.room_id AS t2_room_2
  FROM room r
 WHERE r.room_id > :'t2_room_1'::bigint
   AND NOT EXISTS (
       SELECT 1 FROM tenancy t
        WHERE t.room_id = r.room_id
          AND t.status <> 'cancelled'
          AND daterange(t.start_date, t.end_date)
              && daterange(:'demo_start'::date, :'demo_end'::date)
       )
 ORDER BY r.room_id
 LIMIT 1
\gset

SELECT r.room_id AS t2_room_3
  FROM room r
 WHERE r.room_id > :'t2_room_2'::bigint
   AND NOT EXISTS (
       SELECT 1 FROM tenancy t
        WHERE t.room_id = r.room_id
          AND t.status <> 'cancelled'
          AND daterange(t.start_date, t.end_date)
              && daterange(:'demo_start'::date, :'demo_end'::date)
       )
 ORDER BY r.room_id
 LIMIT 1
\gset

-- Also pick a fourth free room + a second tenant for T1's write in DEMO 3
-- (SERIALIZABLE), so T1's INSERT does not collide with T2's INSERT and the
-- only conflict SSI detects is the read/write dependency.
SELECT r.room_id AS t1_room
  FROM room r
 WHERE r.room_id > :'t2_room_3'::bigint
   AND NOT EXISTS (
       SELECT 1 FROM tenancy t
        WHERE t.room_id = r.room_id
          AND t.status <> 'cancelled'
          AND daterange(t.start_date, t.end_date)
              && daterange(:'demo_start'::date, :'demo_end'::date)
       )
 ORDER BY r.room_id
 LIMIT 1
\gset

SELECT tenant_id AS t1_tenant_id
  FROM tenant
 WHERE tenant_id <> :'t2_tenant_id'::bigint
 ORDER BY tenant_id
 LIMIT 1
\gset

\echo 'Rooms reserved for the three demos:'
\echo '  DEMO 1 T2 room_id  =' :t2_room_1
\echo '  DEMO 2 T2 room_id  =' :t2_room_2
\echo '  DEMO 3 T2 room_id  =' :t2_room_3
\echo '  DEMO 3 T1 room_id  =' :t1_room
\echo '  DEMO 3 T1 tenant_id=' :t1_tenant_id
\echo ''

-- ===========================================================================
-- DEMO 1: READ COMMITTED (the default)
-- ===========================================================================
\echo '======================================================================'
\echo ' DEMO 1: READ COMMITTED (the PostgreSQL default)'
\echo '======================================================================'
\echo ''
\echo ' What we expect:'
\echo '   Terminal 1 reads count(*) FROM tenancy. Terminal 2 inserts a new'
\echo '   tenancy and commits. Terminal 1 reads count(*) AGAIN and SEES the'
\echo '   new row, because each statement in READ COMMITTED sees the latest'
\echo '   committed data.'
\echo ''

-- T1 step 1: BEGIN and read count.
BEGIN;
SET LOCAL default_transaction_isolation = 'read committed';

SELECT count(*) AS rc_count_before FROM tenancy WHERE status = 'active';

\echo ''
\echo ' >>> Terminal 1 is now inside a READ COMMITTED transaction.'
\echo ' >>> Switch to TERMINAL 2 and run this SQL (substitute the values'
\echo ' >>> printed below the SQL):'
\echo ''
\echo '     BEGIN;'
\echo '     INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,'
\echo '                          annual_rent_ngn, status, created_at)'
\echo '     SELECT <ROOM_ID>, <TENANT_ID>,'
\echo '            DATE ''<START>'', DATE ''<END>'','
\echo '            rt.annual_rent_ngn, ''active'', now()'
\echo '       FROM room_type rt'
\echo '       JOIN room r ON r.room_type_id = rt.room_type_id'
\echo '      WHERE r.room_id = <ROOM_ID>;'
\echo '     COMMIT;'
\echo ''
\echo ' >>> Values for THIS run (substitute into the SQL above):'
\echo '       ROOM_ID   =' :t2_room_1
\echo '       TENANT_ID =' :t2_tenant_id
\echo '       START     =' :demo_start
\echo '       END       =' :demo_end
\echo ''

\prompt 'Press Enter in Terminal 1 when Terminal 2 has COMMITted the insert... ' ignored

-- T1 step 2: read count again. Under READ COMMITTED this sees the new row.
SELECT count(*) AS rc_count_after FROM tenancy WHERE status = 'active';

\echo ''
\echo ' Expected: rc_count_after = rc_count_before + 1.'
\echo ' READ COMMITTED re-evaluates the snapshot at each statement, so the'
\echo ' second SELECT sees Terminal 2''s committed insert.'
\echo ''

-- End T1's transaction (rollback so T1 does not leave extra data).
ROLLBACK;

\echo ''
\echo ' [paste real output here - DEMO 1 Terminal 1 output]'
\echo ' [paste real output here - DEMO 1 Terminal 2 output]'
\echo ''

-- ===========================================================================
-- DEMO 2: REPEATABLE READ
-- ===========================================================================
\echo '======================================================================'
\echo ' DEMO 2: REPEATABLE READ'
\echo '======================================================================'
\echo ''
\echo ' What we expect:'
\echo '   Terminal 1 begins a REPEATABLE READ transaction and reads count(*).'
\echo '   Terminal 2 inserts a new tenancy and commits. Terminal 1 reads'
\echo '   count(*) AGAIN and sees the SAME count as before, because the'
\echo '   transaction''s snapshot was fixed at BEGIN time.'
\echo ''

-- T1 step 1: BEGIN REPEATABLE READ and read count.
BEGIN ISOLATION LEVEL REPEATABLE READ;

SELECT count(*) AS rr_count_before FROM tenancy WHERE status = 'active';

\echo ''
\echo ' >>> Terminal 1 is now inside a REPEATABLE READ transaction.'
\echo ' >>> Switch to TERMINAL 2 and run this SQL (substitute the values'
\echo ' >>> printed below the SQL):'
\echo ''
\echo '     BEGIN;'
\echo '     INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,'
\echo '                          annual_rent_ngn, status, created_at)'
\echo '     SELECT <ROOM_ID>, <TENANT_ID>,'
\echo '            DATE ''<START>'', DATE ''<END>'','
\echo '            rt.annual_rent_ngn, ''active'', now()'
\echo '       FROM room_type rt'
\echo '       JOIN room r ON r.room_type_id = rt.room_type_id'
\echo '      WHERE r.room_id = <ROOM_ID>;'
\echo '     COMMIT;'
\echo ''
\echo ' >>> Values for THIS run (substitute into the SQL above):'
\echo '       ROOM_ID   =' :t2_room_2
\echo '       TENANT_ID =' :t2_tenant_id
\echo '       START     =' :demo_start
\echo '       END       =' :demo_end
\echo ''

\prompt 'Press Enter in Terminal 1 when Terminal 2 has COMMITted the insert... ' ignored

-- T1 step 2: read count again. Under REPEATABLE READ this sees the SAME
-- snapshot as step 1 - the new row is invisible.
SELECT count(*) AS rr_count_after FROM tenancy WHERE status = 'active';

\echo ''
\echo ' Expected: rr_count_after = rr_count_before (SAME value).'
\echo ' REPEATABLE READ fixes the snapshot at BEGIN time, so Terminal 1 keeps'
\echo ' seeing the database as it was when the transaction started - even'
\echo ' though Terminal 2 has since committed a new tenancy.'
\echo ''

-- End T1's transaction.
ROLLBACK;

\echo ''
\echo ' [paste real output here - DEMO 2 Terminal 1 output]'
\echo ' [paste real output here - DEMO 2 Terminal 2 output]'
\echo ''

-- ===========================================================================
-- DEMO 3: SERIALIZABLE
-- ===========================================================================
\echo '======================================================================'
\echo ' DEMO 3: SERIALIZABLE (Serializable Snapshot Isolation - SSI)'
\echo '======================================================================'
\echo ''
\echo ' What we expect:'
\echo '   Terminal 1 begins a SERIALIZABLE transaction and reads the SUM of'
\echo '   annual_rent_ngn over active tenancies. Terminal 2 inserts a new'
\echo '   tenancy + rent instalment and commits. Terminal 1 then INSERTs a'
\echo '   new tenancy of its own (a write that depends on the earlier read)'
\echo '   and tries to COMMIT. PostgreSQL''s SSI detects the read/write'
\echo '   dependency between T1 and T2 and aborts T1 with'
\echo '   ERROR: could not serialize access due to read/write dependencies'
\echo '   among transactions  (SQLSTATE 40001 = serialization_failure).'
\echo ''
\echo ' Note: SSI is a conservative detector. It may occasionally let a'
\echo ' truly-serializable schedule through without error, but it never'
\echo ' aborts a transaction that did not actually have a conflict. If your'
\echo ' run commits cleanly, re-run DEMO 3 a second time.'
\echo ''

-- T1 step 1: BEGIN SERIALIZABLE and read the sum of annual rent.
BEGIN ISOLATION LEVEL SERIALIZABLE;

SELECT count(*)     AS ser_count_before,
       COALESCE(sum(annual_rent_ngn), 0) AS ser_rent_sum_before
  FROM tenancy
 WHERE status = 'active';

\echo ''
\echo ' >>> Terminal 1 is now inside a SERIALIZABLE transaction.'
\echo ' >>> Switch to TERMINAL 2 and run this SQL (substitute the values'
\echo ' >>> printed below the SQL):'
\echo ''
\echo '     BEGIN;'
\echo '     INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,'
\echo '                          annual_rent_ngn, status, created_at)'
\echo '     SELECT <ROOM_ID>, <TENANT_ID>,'
\echo '            DATE ''<START>'', DATE ''<END>'','
\echo '            rt.annual_rent_ngn, ''active'', now()'
\echo '       FROM room_type rt'
\echo '       JOIN room r ON r.room_type_id = rt.room_type_id'
\echo '      WHERE r.room_id = <ROOM_ID>;'
\echo '     INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn,'
\echo '                                  paid_at, status, created_at)'
\echo '     SELECT tenancy_id, DATE ''<START>'','
\echo '            annual_rent_ngn, now(), ''paid'', now()'
\echo '       FROM tenancy'
\echo '      WHERE room_id = <ROOM_ID>'
\echo '        AND tenant_id = <TENANT_ID>;'
\echo '     COMMIT;'
\echo ''
\echo ' >>> Values for THIS run (substitute into the SQL above):'
\echo '       ROOM_ID   =' :t2_room_3
\echo '       TENANT_ID =' :t2_tenant_id
\echo '       START     =' :demo_start
\echo '       END       =' :demo_end
\echo ''

\prompt 'Press Enter in Terminal 1 when Terminal 2 has COMMITted its insert... ' ignored

-- T1 step 2: read the sum again. Under SERIALIZABLE (snapshot isolation),
-- T1 still sees the OLD snapshot. The values are the same as before.
SELECT count(*)     AS ser_count_after_read,
       COALESCE(sum(annual_rent_ngn), 0) AS ser_rent_sum_after_read
  FROM tenancy
 WHERE status = 'active';

\echo ''
\echo ' Expected: ser_count_after_read = ser_count_before (SAME).'
\echo ' SERIALIZABLE uses a snapshot like REPEATABLE READ for reads, so the'
\echo ' new committed row from Terminal 2 is still invisible to Terminal 1.'
\echo ''

-- T1 step 3: now do a WRITE that depends on the earlier read. We INSERT a
-- new tenancy of our own. This creates the read/write dependency that SSI
-- checks for.
\echo ' >>> Terminal 1 now performs a WRITE that depends on the read above.'
\echo ' >>> Inserting a new tenancy for tenant ' :t1_tenant_id ' on room ' :t1_room '.'

INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,
                     annual_rent_ngn, status, created_at)
SELECT :'t1_room'::bigint,
       :'t1_tenant_id'::bigint,
       :'demo_start'::date,
       :'demo_end'::date,
       rt.annual_rent_ngn, 'active', now()
  FROM room_type rt
  JOIN room r ON r.room_type_id = rt.room_type_id
 WHERE r.room_id = :'t1_room'::bigint;

\echo ''
\echo ' >>> The INSERT inside Terminal 1''s transaction succeeds (the row is'
\echo ' >>> added to T1''s snapshot). The conflict is detected at COMMIT time.'
\echo ''

-- T1 step 4: try to COMMIT. This is where SSI fires serialization_failure.
\echo ' >>> Attempting COMMIT. Expect serialization_failure (SQLSTATE 40001).'
COMMIT;

\echo ''
\echo ' Expected error message:'
\echo '   ERROR:  could not serialize access due to read/write dependencies'
\echo '   among transactions'
\echo '   DETAIL:  Reason code: Canceled on identification as a pivot, during'
\echo '   commit attempt.'
\echo '   HINT:  The transaction might succeed if retried.'
\echo ''
\echo ' If you see the error above, SSI caught the conflict. If COMMIT'
\echo ' succeeded, SSI''s heuristics judged this schedule to be safely'
\echo ' serializable - re-run DEMO 3 to see the failure.'
\echo ''

-- After a serialization_failure, T1's transaction is already aborted.
-- Make sure no leftover transaction is open.
ROLLBACK;

\echo ''
\echo ' [paste real output here - DEMO 3 Terminal 1 output]'
\echo ' [paste real output here - DEMO 3 Terminal 2 output]'
\echo ''

-- ===========================================================================
-- Cleanup: remove the demo tenancies + instalments that Terminal 2 inserted.
-- We identify them by tenant_id = t2_tenant_id and created_at >= script_start.
-- Also remove any T1 tenancy that survived (shouldn't happen, but be safe).
-- ===========================================================================
\echo '======================================================================'
\echo ' Cleanup: removing demo rows that Terminal 2 inserted'
\echo '======================================================================'
\echo ''

DELETE FROM rent_instalment
 WHERE tenancy_id IN (
     SELECT tenancy_id FROM tenancy
      WHERE tenant_id = :'t2_tenant_id'::bigint
        AND created_at >= :'script_start'::timestamptz
 );

DELETE FROM tenancy
 WHERE tenant_id = :'t2_tenant_id'::bigint
   AND created_at >= :'script_start'::timestamptz;

DELETE FROM rent_instalment
 WHERE tenancy_id IN (
     SELECT tenancy_id FROM tenancy
      WHERE tenant_id = :'t1_tenant_id'::bigint
        AND created_at >= :'script_start'::timestamptz
 );

DELETE FROM tenancy
 WHERE tenant_id = :'t1_tenant_id'::bigint
   AND created_at >= :'script_start'::timestamptz;

\echo ' Cleanup complete.'
\echo ''
\echo ' Verify the cleanup left no demo rows behind:'
SELECT count(*) AS leftover_demo_rows
  FROM tenancy
 WHERE (tenant_id = :'t2_tenant_id'::bigint
        OR tenant_id = :'t1_tenant_id'::bigint)
   AND created_at >= :'script_start'::timestamptz;

\echo ''
\echo '======================================================================'
\echo ' End of isolation_levels.sql'
\echo '======================================================================'
\echo ''
\echo ' Paste the three [paste real output here] blocks above into your LMS'
\echo ' submission, one per isolation level, showing Terminal 1 AND Terminal 2'
\echo ' outputs side by side for each demo.'
\echo ''
