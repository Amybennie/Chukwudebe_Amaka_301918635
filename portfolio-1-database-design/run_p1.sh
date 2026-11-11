#!/usr/bin/env bash
# =============================================================================
# run_p1.sh - one-shot runner for Portfolio 1 (Database Design and Modelling)
# -----------------------------------------------------------------------------
# Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
# Course  : MIT 8103 Advanced Database Systems, Miva Open University
# Study   : Session 1 - Review of Traditional Relational Databases and
#           Advanced Concepts (normalisation, design, advanced constraints)
# -----------------------------------------------------------------------------
# Runs, in order:
#   1. schema.sql          - drop + recreate the public schema, 9 tables,
#                            exclusion / check / unique constraints, triggers.
#   2. seed.sql            - small realistic seed data (4 lodges, 12 room
#                            types, 24 bed-spaces, 12 tenants + guarantors,
#                            8 tenancies, instalments, 2 waitlist, 4 tickets).
#   3. bulk_generator.py   - 32 more lodges, ~15,000 bed-spaces, five
#                            academic sessions, 50,000+ tenancies, instalments,
#                            waitlists, maintenance tickets (single txn).
#   4. constraint_tests.sql- 9 tests that each build their own data and print
#                            PASS only when the intended rule blocked it.
#   5. row-count summary   - one line per table.
#
# Codespaces conventions:
#   * sudo only works as root, so psql runs as the postgres OS user via
#     `sudo runuser -u postgres -- psql ...`. Never `sudo -u postgres`.
#   * All psql connections go through the Unix socket /var/run/postgresql.
#   * The campusnest database is created by setup.sh.
# =============================================================================
set -euo pipefail

DB=campusnest
PSQL="sudo runuser -u postgres -- psql -d ${DB}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo " Portfolio 1 - Database Design and Modelling"
echo " Student: Amaka Benedicta Chukwudebe (2026/A/MIT/0517)"
echo " Study session 1: normalisation, design, advanced constraints"
echo "============================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: schema.sql (fresh schema, ON_ERROR_STOP=1).
# ---------------------------------------------------------------------------
echo "============================================================"
echo " STEP 1/5: schema.sql - drop + recreate schema, 9 tables, constraints"
echo "============================================================"
${PSQL} -v ON_ERROR_STOP=1 -f "${HERE}/schema.sql"
echo ""

# ---------------------------------------------------------------------------
# Step 2: seed.sql (small realistic data, ON_ERROR_STOP=1).
# ---------------------------------------------------------------------------
echo "============================================================"
echo " STEP 2/5: seed.sql - lodges, room types, rooms, tenants, guarantors,"
echo "           tenancies, instalments, waitlist, maintenance"
echo "============================================================"
${PSQL} -v ON_ERROR_STOP=1 -f "${HERE}/seed.sql"
echo ""

# ---------------------------------------------------------------------------
# Step 3: bulk_generator.py (60k tenants + 60k tenancies + ~150k instalments).
# ---------------------------------------------------------------------------
echo "============================================================"
echo " STEP 3/5: bulk_generator.py - 60,000+ tenants and tenancies"
echo "============================================================"
python3 -u "${HERE}/bulk_generator.py"
echo ""

# ---------------------------------------------------------------------------
# Step 4: constraint_tests.sql - every line must say PASS; the runner stops
# if fewer than 9 of 9 pass.
# ---------------------------------------------------------------------------
echo "============================================================"
echo " STEP 4/5: constraint_tests.sql - 9 tests (8 must be blocked, 1 allowed)"
echo "           Each line must say PASS (the rule stopped the bad data)."
echo "============================================================"
${PSQL} -f "${HERE}/constraint_tests.sql" | tee /tmp/p1_constraints.txt
grep -q "9 of 9 constraint tests passed" /tmp/p1_constraints.txt \
    || { echo "ERROR: not every constraint test passed - see the table above"; exit 1; }
echo ""

# ---------------------------------------------------------------------------
# Step 5: row-count summary per table.
# ---------------------------------------------------------------------------
echo "============================================================"
echo " STEP 5/5: row-count summary"
echo "============================================================"
${PSQL} <<'SQL'
SELECT 'lodge'              AS table_name, count(*) FROM lodge
UNION ALL SELECT 'room_type',          count(*) FROM room_type
UNION ALL SELECT 'room',               count(*) FROM room
UNION ALL SELECT 'tenant',             count(*) FROM tenant
UNION ALL SELECT 'guarantor',          count(*) FROM guarantor
UNION ALL SELECT 'tenancy',            count(*) FROM tenancy
UNION ALL SELECT 'rent_instalment',    count(*) FROM rent_instalment
UNION ALL SELECT 'waitlist_entry',     count(*) FROM waitlist_entry
UNION ALL SELECT 'maintenance_ticket', count(*) FROM maintenance_ticket
ORDER BY table_name;
SQL
echo ""

echo "============================================================"
echo " Portfolio 1 complete."
echo " What to screenshot for the LMS submission:"
echo "   1. The STEP 1 output (schema created, no errors)."
echo "   2. The STEP 2 output (seed loaded, no errors)."
echo "   3. The STEP 3 bulk_generator.py final summary block"
echo "      (rows inserted per table, elapsed seconds)."
echo "   4. The STEP 4 table showing 9 of 9 constraint tests PASS."
echo "   5. The STEP 5 row-count summary."
echo "============================================================"
