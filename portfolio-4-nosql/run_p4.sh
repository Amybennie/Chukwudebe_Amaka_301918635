#!/usr/bin/env bash
# =============================================================================
# run_p4.sh - Portfolio 4 (NoSQL / MongoDB) one-shot runner
# Student : Amaka Benedicta Chukwudebe
# Matric  : 2026/A/MIT/0517
# Course  : MIT 8103 Advanced Database Systems
# Cohort  : September 2026 (2026/2027 First Semester)
# Case    : CampusNest - Private Student Accommodation Booking
#
# What this script does
# ---------------------
#   1. Verifies that mongod is running (db.runCommand({ping:1})).
#   2. Drops the campusnest_nosql database so each run starts clean.
#   3. Runs schema_validation.js - creates maintenance_tickets with a
#      $jsonSchema validator and inserts 4 valid example docs + 1 invalid doc.
#   4. Runs seed.js - bulk inserts 42,000+ maintenance ticket documents.
#   5. Prints db.maintenance_tickets.estimatedDocumentCount().
#   6. Runs aggregations.js - three business-question aggregations; the
#      results are pretty-printed and the README expects the student to paste
#      the real output where it says [paste real output here].
#   7. Runs index_demo.js TWICE conceptually (the script itself does the
#      BEFORE / AFTER in one pass) and prints [paste real output here] for
#      the COLLSCAN vs IXSCAN comparison.
#
# Codespaces conventions
# ----------------------
#   * MongoDB 8 is installed by setup.sh and started with
#     `sudo runuser -u mongodb -- mongod --config /etc/mongod.conf --fork`.
#   * mongosh connects on mongodb://127.0.0.1:27017 (no auth in dev).
#   * JS files are run with:
#       mongosh mongodb://127.0.0.1:27017/campusnest_nosql <file.js
#
# Run
# ---
#   chmod +x run_p4.sh
#   ./run_p4.sh
#
# Honest results policy
# ---------------------
#   This script never fabricates explain() output, aggregation results, or
#   timings. Where real output would appear, the literal placeholder
#   `[paste real output here]` is printed by the JS files; the student is
#   expected to copy the real terminal output into README.md after running.
# =============================================================================
set -euo pipefail

MONGOSH="mongosh"
URI="mongodb://127.0.0.1:27017/campusnest_nosql"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

header() {
    echo
    echo "============================================================"
    echo " $1"
    echo "============================================================"
}

# ---------------------------------------------------------------------------
# 1. Verify mongod is running.
# ---------------------------------------------------------------------------
header "STEP 1 - Verify mongod is running (db.runCommand({ping:1}))"
if ! $MONGOSH --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1; then
    echo "[ERROR] mongod is not responding on $URI."
    echo "        Start it first with:  sudo runuser -u mongodb -- mongod --config /etc/mongod.conf --fork"
    echo "        Then re-run this script."
    exit 1
fi
echo "[OK] mongod is responding."
$MONGOSH --quiet --eval 'db.runCommand({ping:1})'

# ---------------------------------------------------------------------------
# 2. Drop the campusnest_nosql database - fresh start.
# ---------------------------------------------------------------------------
header "STEP 2 - Drop campusnest_nosql (fresh start)"
$MONGOSH --quiet --eval '
    db.getSiblingDB("campusnest_nosql").dropDatabase();
    print("Dropped campusnest_nosql. Databases now:");
    printjson(db.adminCommand({listDatabases:1}).databases.map(function(d){return d.name;}));
'

# ---------------------------------------------------------------------------
# 3. Run schema_validation.js.
# ---------------------------------------------------------------------------
header "STEP 3 - schema_validation.js (create collection with \$jsonSchema validator)"
$MONGOSH "$URI" "$SCRIPT_DIR/schema_validation.js"

# ---------------------------------------------------------------------------
# 4. Run seed.js (40,000+ documents).
# ---------------------------------------------------------------------------
header "STEP 4 - seed.js (42,000 tickets raised by REAL tenants from PostgreSQL)"
echo "Exporting real tenancies (tenant, lodge, bed-space, dates) from PostgreSQL to pg_refs.json ..."
sudo runuser -u postgres -- psql -d campusnest -tAq -c "
SELECT json_build_object(
  'lodge_count', (SELECT count(*) FROM lodge),
  'tenancies', json_agg(json_build_object(
     'tenant_id', t.tenant_id, 'tenant_name', tn.full_name, 'lodge_id', l.lodge_id,
     'lodge_name', l.name, 'institution', l.nearest_school, 'room_code', r.room_code,
     'start', t.start_date, 'end', t.end_date)))
  FROM tenancy t JOIN tenant tn USING (tenant_id) JOIN room r USING (room_id) JOIN lodge l ON l.lodge_id = r.lodge_id
 WHERE t.status <> 'cancelled' AND t.start_date <= CURRENT_DATE;" > /tmp/pg_refs.json
echo "pg_refs.json: $(du -h /tmp/pg_refs.json | cut -f1)"
$MONGOSH "$URI" --eval "var refsFile='/tmp/pg_refs.json'" "$SCRIPT_DIR/seed.js"

# ---------------------------------------------------------------------------
# 5. Print the final document count.
# ---------------------------------------------------------------------------
header "STEP 5 - db.maintenance_tickets.estimatedDocumentCount()"
$MONGOSH --quiet "$URI" --eval '
    print("estimatedDocumentCount = " + db.maintenance_tickets.estimatedDocumentCount());
    print("The portfolio requires 40,000+ documents.");
'

# ---------------------------------------------------------------------------
# 6. Run aggregations.js (AGG-1, AGG-2, AGG-3).
# ---------------------------------------------------------------------------
header "STEP 6 - aggregations.js (AGG-1 lodge x category, AGG-2 avg resolution days, AGG-3 repeat problems)"
$MONGOSH "$URI" "$SCRIPT_DIR/aggregations.js"

# ---------------------------------------------------------------------------
# 7. Run index_demo.js (BEFORE: COLLSCAN, AFTER: IXSCAN).
# ---------------------------------------------------------------------------
header "STEP 7 - index_demo.js (BEFORE: COLLSCAN, AFTER: IXSCAN)"
echo "The script drops indexes, runs explain() once (expect COLLSCAN),"
echo "creates the compound index {lodge_id:1, status:1, category:1, reported_at:-1},"
echo "then runs explain() again (expect IXSCAN)."
$MONGOSH "$URI" "$SCRIPT_DIR/index_demo.js" | tee "$SCRIPT_DIR/index_demo_output.log"

# ---------------------------------------------------------------------------
# Done.
# ---------------------------------------------------------------------------
header "PORTFOLIO 4 RUN COMPLETE"
cat <<'EOF'

What to screenshot for the LMS submission
-----------------------------------------
  1. STEP 3 output - the listCollections info showing the $jsonSchema
     validator on maintenance_tickets, plus the 4 valid example docs and
     the rejected invalid doc.
  2. STEP 5 output - estimatedDocumentCount() >= 40,000.
  3. STEP 6 output - the three aggregations (AGG-1, AGG-2, AGG-3).
  4. STEP 7 output - the BEFORE (COLLSCAN) and AFTER (IXSCAN) explain()
     summaries plus the side-by-side comparison.

Then paste the real outputs into README.md at each [paste real output here]
placeholder and commit to GitHub:

  git add portfolio-4-nosql/
  git commit -m "Portfolio 4: NoSQL MongoDB maintenance tickets (schema validator, 42k docs, aggregations, COLLSCAN->IXSCAN)"
  git push

EOF
