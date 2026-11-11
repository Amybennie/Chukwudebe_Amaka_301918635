-- =============================================================================
-- deadlock_demo.sql
-- Portfolio 3 - Transactions and Concurrency
-- Student : Amaka Benedicta Chukwudebe
-- Matric  : 2026/A/MIT/0517
-- Course  : MIT 8103 Advanced Database Systems, Miva Open University
-- Case    : CampusNest - Private Student Accommodation Booking
-- =============================================================================
--
-- What this file demonstrates
-- ---------------------------
--   A classic two-session deadlock, on the CampusNest tenancy table:
--
--     Terminal 1                            Terminal 2
--     -----------                           -----------
--     BEGIN;
--     UPDATE tenancy ... WHERE id=1;  (locks row 1)
--                                           BEGIN;
--                                           UPDATE tenancy ... WHERE id=2;  (locks row 2)
--     UPDATE tenancy ... WHERE id=2;  (waits for T2's lock on row 2)
--                                           UPDATE tenancy ... WHERE id=1;  (waits for T1's lock on row 1)
--                                           ^^^ DEADLOCK ^^^
--     --> PostgreSQL's deadlock detector runs every ~1 second.
--         It picks one of the two transactions as the victim, aborts it
--         with ERROR: deadlock detected, and the other transaction
--         succeeds (its UPDATE unblocks and proceeds).
--
--   The UPDATE statements use `annual_rent_ngn = annual_rent_ngn` which is a
--   no-op value assignment: the row's value does not change, but PostgreSQL
--   still acquires the row-level lock. This lets us demonstrate the deadlock
--   without permanently changing any data.
--
-- How to run this file
-- --------------------
--   1. Run this file ONCE in Terminal 1 to pick the two tenancy IDs:
--          sudo runuser -u postgres -- psql -d campusnest -f deadlock_demo.sql
--      or, from inside psql:  \i deadlock_demo.sql
--   2. Open TWO separate terminals, both connected to campusnest:
--          sudo runuser -u postgres -- psql -d campusnest
--   3. Follow the numbered steps the script echoes, alternating between
--      Terminal 1 and Terminal 2 exactly as written. The deadlock requires
--      precise ordering, so do not skip ahead.
--
--   This file does NOT execute the deadlock itself - it cannot, because a
--   single psql session cannot hold two open transactions at once. It only
--   picks the two tenancy IDs and prints the step-by-step instructions.
-- =============================================================================

\set ON_ERROR_STOP off
\pset pager off
\pset format aligned

\echo ''
\echo '======================================================================'
\echo ' Deadlock Demo - MIT 8103 Portfolio 3'
\echo ' Student: Amaka Benedicta Chukwudebe (2026/A/MIT/0517)'
\echo '======================================================================'
\echo ''
\echo ' This file picks two existing tenancy_ids to lock against, then prints'
\echo ' the step-by-step instructions for you to follow in TWO terminals.'
\echo ''
\echo ' Open two terminals, both connected as:'
\echo '     sudo runuser -u postgres -- psql -d campusnest'
\echo ''

-- ---------------------------------------------------------------------------
-- Pick two existing tenancy IDs for the demo.
-- We need rows that already exist (so the UPDATE finds them and locks them).
-- Prefer 'active' tenancies; if there are fewer than 2, fall back to any.
-- ---------------------------------------------------------------------------
SELECT tenancy_id  AS deadlock_t1_id,
       room_id     AS deadlock_t1_room,
       tenant_id   AS deadlock_t1_tenant
  FROM tenancy
 WHERE status = 'active'
 ORDER BY tenancy_id
 LIMIT 1
\gset

SELECT tenancy_id  AS deadlock_t2_id,
       room_id     AS deadlock_t2_room,
       tenant_id   AS deadlock_t2_tenant
  FROM tenancy
 WHERE status = 'active'
   AND tenancy_id <> COALESCE(:'deadlock_t1_id'::bigint, -1)
 ORDER BY tenancy_id
 LIMIT 1
\gset

-- If the active-tenancy lookup did not yield two IDs, fall back to any rows.
SELECT tenancy_id  AS deadlock_t1_id,
       room_id     AS deadlock_t1_room,
       tenant_id   AS deadlock_t1_tenant
  FROM tenancy
 WHERE :'deadlock_t1_id'::bigint IS NULL
 ORDER BY tenancy_id
 LIMIT 1
\gset

SELECT tenancy_id  AS deadlock_t2_id,
       room_id     AS deadlock_t2_room,
       tenant_id   AS deadlock_t2_tenant
  FROM tenancy
 WHERE :'deadlock_t2_id'::bigint IS NULL
   AND tenancy_id <> COALESCE(:'deadlock_t1_id'::bigint, -1)
 ORDER BY tenancy_id
 LIMIT 1
\gset

\echo ' Two tenancy IDs chosen for the deadlock demo:'
\echo '   Terminal 1 will lock tenancy_id =' :deadlock_t1_id
\echo '                  (room_id =' :deadlock_t1_room ', tenant_id =' :deadlock_t1_tenant ')'
\echo '   Terminal 2 will lock tenancy_id =' :deadlock_t2_id
\echo '                  (room_id =' :deadlock_t2_room ', tenant_id =' :deadlock_t2_tenant ')'
\echo ''

\echo ' If either ID above is empty, your tenancy table has fewer than 2 rows.'
\echo ' Run Portfolio 1 first to seed the database.'
\echo ''

\echo '======================================================================'
\echo ' STEP-BY-STEP INSTRUCTIONS (follow in TWO terminals)'
\echo '======================================================================'
\echo ''
\echo ' The deadlock requires precise ordering. Type ONE command at a time'
\echo ' and WAIT where indicated.'
\echo ''

\echo ' -------------------------------------------------------------------'
\echo ' STEP 1 - Terminal 1: BEGIN and lock tenancy_id =' :deadlock_t1_id
\echo ' -------------------------------------------------------------------'
\echo ' In TERMINAL 1, type:'
\echo ''
\echo '     BEGIN;'
\echo '     UPDATE tenancy SET annual_rent_ngn = annual_rent_ngn'
\echo '      WHERE tenancy_id = ' :deadlock_t1_id ';'
\echo ''
\echo ' Expected output:  UPDATE 1   (Terminal 1 now holds the row lock on'
\echo '                              tenancy_id =' :deadlock_t1_id ')'
\echo ''
\echo ' DO NOT COMMIT. Leave Terminal 1''s transaction open.'
\echo ''
\echo ' [paste real output here - STEP 1 Terminal 1]'
\echo ''

\echo ' -------------------------------------------------------------------'
\echo ' STEP 2 - Terminal 2: BEGIN and lock tenancy_id =' :deadlock_t2_id
\echo ' -------------------------------------------------------------------'
\echo ' Switch to TERMINAL 2 and type:'
\echo ''
\echo '     BEGIN;'
\echo '     UPDATE tenancy SET annual_rent_ngn = annual_rent_ngn'
\echo '      WHERE tenancy_id = ' :deadlock_t2_id ';'
\echo ''
\echo ' Expected output:  UPDATE 1   (Terminal 2 now holds the row lock on'
\echo '                              tenancy_id =' :deadlock_t2_id ')'
\echo ''
\echo ' DO NOT COMMIT. Leave Terminal 2''s transaction open.'
\echo ''
\echo ' [paste real output here - STEP 2 Terminal 2]'
\echo ''

\echo ' -------------------------------------------------------------------'
\echo ' STEP 3 - Terminal 1: try to lock tenancy_id =' :deadlock_t2_id
\echo '           (Terminal 2 already holds this lock -> Terminal 1 BLOCKS)'
\echo ' -------------------------------------------------------------------'
\echo ' Switch back to TERMINAL 1 and type:'
\echo ''
\echo '     UPDATE tenancy SET annual_rent_ngn = annual_rent_ngn'
\echo '      WHERE tenancy_id = ' :deadlock_t2_id ';'
\echo ''
\echo ' Expected behaviour: Terminal 1''s prompt DOES NOT return. The UPDATE'
\echo ' is BLOCKED, waiting for Terminal 2 to release its lock on'
\echo ' tenancy_id =' :deadlock_t2_id '. This is NOT the deadlock yet - this'
\echo ' is just a normal lock wait.'
\echo ''
\echo ' DO NOT press Ctrl+C. Leave Terminal 1 waiting.'
\echo ''
\echo ' [paste real output here - STEP 3 Terminal 1 (will be empty until STEP 4 completes)]'
\echo ''

\echo ' -------------------------------------------------------------------'
\echo ' STEP 4 - Terminal 2: try to lock tenancy_id =' :deadlock_t1_id
\echo '           (Terminal 1 holds this lock AND is waiting for Terminal 2'
\echo '            -> DEADLOCK forms here)'
\echo ' -------------------------------------------------------------------'
\echo ' Switch to TERMINAL 2 and type:'
\echo ''
\echo '     UPDATE tenancy SET annual_rent_ngn = annual_rent_ngn'
\echo '      WHERE tenancy_id = ' :deadlock_t1_id ';'
\echo ''
\echo ' Expected behaviour: Within about 1 second, PostgreSQL''s deadlock'
\echo ' detector notices the cycle:'
\echo '   T1 waits for T2 (on tenancy_id =' :deadlock_t2_id ')'
\echo '   T2 waits for T1 (on tenancy_id =' :deadlock_t1_id ')'
\echo ' and PostgreSQL picks ONE transaction as the victim. The victim''s'
\echo ' UPDATE is aborted with:'
\echo ''
\echo '     ERROR:  deadlock detected'
\echo '     DETAIL:  Process <PID> waits for ShareLock on transaction <XID>'
\echo '             blocked by process <PID>.'
\echo '     HINT:  See server log for query details.'
\echo ''
\echo ' The OTHER transaction''s blocked UPDATE then proceeds and returns'
\echo ' UPDATE 1.'
\echo ''
\echo ' Which terminal is the victim is non-deterministic - either Terminal 1'
\echo ' or Terminal 2 could be aborted. Capture BOTH terminals'' output.'
\echo ''
\echo ' [paste real output here - STEP 4 Terminal 1 (either UPDATE 1 or ERROR: deadlock detected)]'
\echo ' [paste real output here - STEP 4 Terminal 2 (either UPDATE 1 or ERROR: deadlock detected)]'
\echo ''

\echo ' -------------------------------------------------------------------'
\echo ' STEP 5 - Finish both transactions'
\echo ' -------------------------------------------------------------------'
\echo ' In the terminal that got UPDATE 1 (the survivor), commit:'
\echo ''
\echo '     COMMIT;'
\echo ''
\echo ' In the terminal that got ERROR: deadlock detected (the victim), the'
\echo ' transaction is already aborted. Run ROLLBACK to clean up the prompt:'
\echo ''
\echo '     ROLLBACK;'
\echo ''
\echo ' Expected: the survivor prints COMMIT, the victim prints ROLLBACK.'
\echo ''
\echo ' [paste real output here - STEP 5 survivor COMMIT]'
\echo ' [paste real output here - STEP 5 victim ROLLBACK]'
\echo ''

\echo '======================================================================'
\echo ' HOW TO RETRY AFTER A DEADLOCK'
\echo '======================================================================'
\echo ''
\echo ' A deadlock is not a bug in your application - it is PostgreSQL''s way'
\echo ' of resolving an unresolvable lock cycle. The standard pattern is:'
\echo ''
\echo '   1. Catch the SQLSTATE 40P01 (deadlock_detected) error in the'
\echo '      application.'
\echo '   2. ROLLBACK the aborted transaction (PostgreSQL does this for you'
\echo '      automatically - the transaction is already aborted by the time'
\echo '      you see the error).'
\echo '   3. RE-RUN the whole transaction from the BEGIN. Typically you'
\echo '      retry 2-3 times with a short sleep before giving up.'
\echo ''
\echo ' In SQL, the retry is simply: re-issue BEGIN; UPDATE ...; UPDATE ...;'
\echo ' COMMIT;  in the victim terminal.'
\echo ''
\echo ' To demonstrate the retry, in the victim terminal type:'
\echo ''
\echo '     BEGIN;'
\echo '     UPDATE tenancy SET annual_rent_ngn = annual_rent_ngn'
\echo '      WHERE tenancy_id = ' :deadlock_t1_id ';'
\echo '     UPDATE tenancy SET annual_rent_ngn = annual_rent_ngn'
\echo '      WHERE tenancy_id = ' :deadlock_t2_id ';'
\echo '     COMMIT;'
\echo ''
\echo ' Expected: BEGIN, UPDATE 1, UPDATE 1, COMMIT. The retry succeeds'
\echo ' because there is no concurrent transaction competing for the locks'
\echo ' any more.'
\echo ''
\echo ' [paste real output here - retry in the victim terminal]'
\echo ''

\echo '======================================================================'
\echo ' WHY POSTGRESQL BEHAVES THIS WAY'
\echo '======================================================================'
\echo ''
\echo ' - Row-level locks in PostgreSQL do NOT cause deadlocks on their own.'
\echo '   A deadlock requires a CYCLE: T1 waits for T2, T2 waits for T1.'
\echo '   Locks acquired in the SAME ORDER by all transactions never cycle.'
\echo ''
\echo ' - PostgreSQL''s deadlock detector is a background process that runs'
\echo '   every deadlock_timeout milliseconds (default 1 second). It scans'
\echo '   the lock-wait graph for cycles and aborts one transaction per'
\echo '   cycle. The victim is chosen to minimise the work lost.'
\echo ''
\echo ' - In the CampusNest booking system, you avoid deadlocks by always'
\echo '   locking rooms in a canonical order (e.g. ascending room_id) inside'
\echo '   reserve_room(). The reserve_room() function in this portfolio'
\echo '   locks exactly ONE room per transaction, so it cannot deadlock'
\echo '   with another invocation of itself. Deadlocks become possible only'
\echo '   when a transaction locks multiple resources in conflicting orders.'
\echo ''
\echo ' - ACID perspective: the deadlock abort is part of ATOMICITY - the'
\echo '   victim transaction is rolled back completely, leaving the database'
\echo '   in the state it was in before the transaction began. No partial'
\echo '   updates survive. CONSISTENCY is preserved because the exclusion'
\echo '   constraints from Portfolio 1 still hold; ISOLATION is preserved'
\echo '   because the surviving transaction''s locks prevent any concurrent'
\echo '   writer from seeing an inconsistent state; DURABILITY applies once'
\echo '   the surviving transaction COMMITs.'
\echo ''

\echo '======================================================================'
\echo ' End of deadlock_demo.sql'
\echo '======================================================================'
\echo ''
\echo ' Paste the five [paste real output here] blocks above into your LMS'
\echo ' submission. Capture BOTH terminals for STEP 4 (the deadlock moment)'
\echo ' and STEP 5 (the aftermath), plus the retry block.'
\echo ''
