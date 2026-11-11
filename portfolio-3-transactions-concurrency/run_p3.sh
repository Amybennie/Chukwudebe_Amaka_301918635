#!/usr/bin/env bash
# =============================================================================
# run_p3.sh - Portfolio 3: Transactions and Concurrency (no typing needed)
# Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
# Case    : CampusNest - Private Student Accommodation Booking
# -----------------------------------------------------------------------------
#   1. Check Portfolio 1 data is loaded.
#   2. Load reserve_room.sql (reserve_room() + next_session_start()).
#   3. COMMIT demo   - a student reserves a bed, payment succeeds, COMMIT.
#   4. ROLLBACK demo - a student reserves a bed, payment fails, ROLLBACK.
#   5. run_race_demos.py - six two-session concurrency scenarios, saved to
#      race_demos_output.log (bug, exclusion constraint, SKIP LOCKED,
#      SERIALIZABLE, READ COMMITTED vs REPEATABLE READ, deadlock + fix).
# The older two-terminal guides (isolation_levels.sql, deadlock_demo.sql,
# race_condition_demo.md) are kept for anyone who wants to repeat a part by
# hand; run_race_demos.py does the same things automatically.
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
DB=campusnest
PSQL=(sudo runuser -u postgres -- psql -d "$DB" -v ON_ERROR_STOP=1)

hr() { echo; echo "============================================================"; echo " $1"; echo "============================================================"; }

hr "Portfolio 3 - Transactions and Concurrency"
echo " Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)"
echo " Started : $(date '+%Y-%m-%d %H:%M:%S')"

hr "[1/5] Checking Portfolio 1 data"
N=$("${PSQL[@]}" -tAc "SELECT count(*) FROM tenancy")
[ "$N" -ge 50000 ] || { echo "ERROR: only $N tenancies - run portfolio 1 first."; exit 1; }
echo " $N tenancies present. OK."

hr "[2/5] Loading reserve_room.sql"
"${PSQL[@]}" -f reserve_room.sql

# A student with no tenancy running into next session and not on a waitlist,
# and the room type with the most free beds next session.
PICK_SQL="
SELECT tn.tenant_id AS tid, tn.full_name AS tname
  FROM tenant tn
 WHERE NOT EXISTS (SELECT 1 FROM tenancy t WHERE t.tenant_id = tn.tenant_id
                     AND t.status <> 'cancelled' AND t.end_date > next_session_start())
   AND NOT EXISTS (SELECT 1 FROM waitlist_entry w WHERE w.tenant_id = tn.tenant_id)
 ORDER BY tn.tenant_id OFFSET :off LIMIT 1
\gset
SELECT rt.room_type_id AS rtid, l.name || ' - ' || rt.name AS rtname, rt.annual_rent_ngn AS rent,
       count(*) AS free_beds
  FROM room r JOIN room_type rt USING (room_type_id) JOIN lodge l ON l.lodge_id = r.lodge_id
 WHERE NOT EXISTS (SELECT 1 FROM tenancy t WHERE t.room_id = r.room_id AND t.status <> 'cancelled'
                     AND daterange(t.start_date, t.end_date)
                         && daterange(next_session_start(), (next_session_start() + interval '12 months')::date))
 GROUP BY rt.room_type_id, l.name, rt.name, rt.annual_rent_ngn
 ORDER BY free_beds DESC, rt.room_type_id LIMIT 1
\gset
\echo ' Student   :' :tid :'tname'
\echo ' Room type :' :rtid :'rtname' '- free beds next session:' :free_beds '- rent NGN' :rent
"

hr "[3/5] COMMIT demo - payment succeeds"
"${PSQL[@]}" -v off=0 <<SQL
${PICK_SQL}
SELECT count(*) AS tenancies_before FROM tenancy WHERE tenant_id = :tid;
BEGIN;
SELECT outcome, tenancy_id, room_code, message FROM reserve_room(:tid, :rtid) \gset r_
\echo ' reserve_room ->' :r_outcome :'r_message'
\echo ' Payment gateway says: SUCCESS  -> COMMIT'
COMMIT;
SELECT count(*) AS tenancies_after FROM tenancy WHERE tenant_id = :tid;
SELECT t.tenancy_id, r.room_code, t.start_date, t.end_date, t.status,
       i.amount_ngn AS first_instalment_ngn, i.status AS instalment_status
  FROM tenancy t JOIN room r USING (room_id) JOIN rent_instalment i USING (tenancy_id)
 WHERE t.tenancy_id = :r_tenancy_id;
\echo ' The tenancy AND its first instalment were saved together (atomic + durable).'
SQL

hr "[4/5] ROLLBACK demo - payment fails"
"${PSQL[@]}" -v off=1 <<SQL
${PICK_SQL}
SELECT count(*) AS tenancies_before FROM tenancy WHERE tenant_id = :tid;
BEGIN;
SELECT outcome, tenancy_id, room_code, message FROM reserve_room(:tid, :rtid) \gset r_
\echo ' reserve_room ->' :r_outcome :'r_message'
SELECT count(*) AS visible_inside_transaction FROM tenancy WHERE tenancy_id = :r_tenancy_id;
\echo ' Payment gateway says: DECLINED -> ROLLBACK'
ROLLBACK;
SELECT count(*) AS tenancies_after FROM tenancy WHERE tenant_id = :tid;
SELECT count(*) AS rows_left_for_that_tenancy_id FROM tenancy WHERE tenancy_id = :r_tenancy_id;
SELECT count(*) AS instalments_left FROM rent_instalment WHERE tenancy_id = :r_tenancy_id;
\echo ' Tenancy and instalment were both undone - all or nothing (atomicity).'
SQL

hr "[5/5] Six concurrency scenarios with two real sessions"
python3 -u run_race_demos.py 2>&1 | tee race_demos_output.log

hr "Portfolio 3 complete"
echo " Evidence: this output (p3_output.log) and race_demos_output.log"
