#!/usr/bin/env bash
# =============================================================================
# run_p2.sh - Portfolio 2: Query Processing and Optimisation
# Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
# Case    : CampusNest - Private Student Accommodation Booking
# -----------------------------------------------------------------------------
#   0. Check Portfolio 1's bulk data is loaded (50,000+ tenancies).
#   1. BASELINE: drop every helper index that does not back a constraint
#      (primary keys, UNIQUE and the EXCLUDE constraints stay), then ANALYZE,
#      so the BEFORE plans show what the planner does with no tuning.
#   2. queries.sql        - the 7 business queries and their results.
#   3. explain_before.sql - EXPLAIN ANALYZE of all 7, saved to explain_before.log
#   4. indexes.sql        - the tuning indexes, then ANALYZE.
#   5. explain_after.sql  - EXPLAIN ANALYZE of all 7, saved to explain_after.log
#   6. p2_timings.md      - a before/after table built from the two real logs.
# Re-runnable: step 1 resets the indexes every time.
# =============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DB=campusnest
PSQL=(sudo runuser -u postgres -- psql -d "$DB" -v ON_ERROR_STOP=1)

echo "=============================================================="
echo " MIT 8103 - Portfolio 2: Query Processing and Optimisation"
echo " Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)"
echo " Case    : CampusNest"
echo "=============================================================="

echo
echo "[Step 0] Checking Portfolio 1 data ..."
N=$("${PSQL[@]}" -tAc "SELECT count(*) FROM tenancy;")
if [ "$N" -lt 50000 ]; then
    echo "ERROR: only $N tenancies. Run ../portfolio-1-database-design/run_p1.sh first."
    exit 1
fi
"${PSQL[@]}" -c "
SELECT 'tenancy' AS table_name, count(*) AS rows FROM tenancy
UNION ALL SELECT 'rent_instalment', count(*) FROM rent_instalment
UNION ALL SELECT 'tenant', count(*) FROM tenant
UNION ALL SELECT 'room (bed-spaces)', count(*) FROM room
UNION ALL SELECT 'maintenance_ticket', count(*) FROM maintenance_ticket;"

echo "[Step 1] BASELINE - dropping helper indexes (constraint indexes stay) ..."
"${PSQL[@]}" -q <<'SQL'
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT i.indexrelid::regclass AS idx
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conindid = i.indexrelid)
  LOOP
    EXECUTE 'DROP INDEX ' || r.idx;
    RAISE NOTICE 'dropped %', r.idx;
  END LOOP;
END $$;
ANALYZE;
SQL
echo "Indexes left for the BEFORE run (all back a PK, UNIQUE or EXCLUDE constraint):"
"${PSQL[@]}" -c "SELECT tablename, indexname FROM pg_indexes WHERE schemaname='public'
                 AND tablename IN ('tenancy','rent_instalment','tenant','room','maintenance_ticket','waitlist_entry')
                 ORDER BY 1,2;"

echo "[Step 2] queries.sql - the 7 business queries"
"${PSQL[@]}" -f queries.sql

echo "[Step 3] explain_before.sql - EXPLAIN ANALYZE before tuning"
"${PSQL[@]}" -f explain_before.sql | tee explain_before.log

echo "[Step 4] indexes.sql - creating the tuning indexes"
"${PSQL[@]}" -f indexes.sql

echo "[Step 5] explain_after.sql - EXPLAIN ANALYZE after tuning"
"${PSQL[@]}" -f explain_after.sql | tee explain_after.log

echo "[Step 6] Building p2_timings.md from the two real logs"
python3 - <<'PY'
import re
def parse(fn):
    out, q = {}, None
    for line in open(fn):
        m = re.match(r"===== (Q\d+): (.*?) - (BEFORE|AFTER) INDEXES", line)
        if m:
            q = m.group(1); out[q] = {'name': m.group(2), 'scans': [], 'ms': None}
            continue
        if q:
            for node in re.findall(r"((?:Parallel )?(?:Seq Scan|Index Only Scan|Index Scan|Bitmap Index Scan)(?: using \w+)? on \w+(?: \w+)?)", line):
                node = re.sub(r" \w+$", "", node) if " on " in node and len(node.split(" on ")[1].split()) > 1 else node
                if node not in out[q]['scans']:
                    out[q]['scans'].append(node)
            m = re.search(r"Execution Time: ([\d.]+) ms", line)
            if m:
                out[q]['ms'] = float(m.group(1))
    return out
b, a = parse('explain_before.log'), parse('explain_after.log')
rows = ["| Query | Before: scans used | Before ms | After: scans used | After ms | Change |",
        "|---|---|---|---|---|---|"]
for q in sorted(b, key=lambda k: int(k[1:])):
    bm, am = b[q]['ms'], a.get(q, {}).get('ms')
    ch = f"{(bm - am) / bm * 100:+.0f}% faster" if bm and am and am < bm else (f"{(am - bm) / bm * 100:.0f}% slower" if bm and am else "-")
    ch = ch.replace("+", "")
    rows.append(f"| {q} {b[q]['name']} | {'; '.join(b[q]['scans'])} | {bm} | {'; '.join(a.get(q, {}).get('scans', []))} | {am} | {ch} |")
text = ("# Portfolio 2 - real before/after timings\n\n"
        "Built automatically by run_p2.sh from explain_before.log and explain_after.log "
        "(this run, this Codespace). Times are single runs and vary a little between runs.\n\n"
        + "\n".join(rows) + "\n")
open('p2_timings.md', 'w').write(text)
print(text)
PY

echo "=============================================================="
echo " Portfolio 2 complete. Evidence files in this folder:"
echo "   explain_before.log, explain_after.log, p2_timings.md"
echo "=============================================================="
