#!/usr/bin/env bash
# =============================================================================
# run_p5.sh - Portfolio 5 runner (Distributed and Cloud Database Exercise)
# Student : Amaka Benedicta Chukwudebe
# Matric  : 2026/A/MIT/0517
# Course  : MIT 8103 Advanced Database Systems (Miva Open University)
# Case    : CampusNest - Private Student Accommodation Booking
#
# What this script does
# ---------------------
#   1. Verifies Portfolio 1's schema (the 9 CampusNest tables) and that the
#      rent_instalment table has data to partition.
#   2. Runs partition.sql, which converts rent_instalment from a flat heap
#      into a RANGE PARTITIONED table (one partition per academic session +
#      a default partition). partition.sql also prints the partition list
#      and rows per partition.
#   3. Prints the partition list and row counts a second time.
#   4. Runs replication_demo.sh, which builds and tests the streaming read
#      replica on port 5433 in one go (no systemctl - Codespaces has none),
#      saving replication_output.log.
#   5. Prints a clear message directing the student to read
#      cloud_architecture.md for the cloud + NDPA 2023 design.
#
# Codespaces conventions
# ----------------------
#   * The codespace user can sudo only as root, so every psql that must run
#     as the postgres OS user uses:
#         sudo runuser -u postgres -- psql ...
#     NEVER  sudo -u postgres  (it fails in Codespaces).
#   * All psql connections go through the Unix socket
#     host=/var/run/postgresql - no TCP, no password.
#   * PostgreSQL 16 config dir : /etc/postgresql/16/main/
#   * pg_ctl binary            : /usr/lib/postgresql/16/bin/pg_ctl
#
# Prerequisite
# ------------
#   Portfolio 1 MUST have been run first - rent_instalment and its 100k+
#   rows from bulk_generator.py must already exist in the campusnest
#   database. This script will fail loudly if they do not.
#
# Run it
# ------
#   cd portfolio-5-distributed-cloud
#   chmod +x run_p5.sh
#   ./run_p5.sh
# =============================================================================
set -euo pipefail

DB="campusnest"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PSQL="sudo runuser -u postgres -- psql -d ${DB} -v ON_ERROR_STOP=1"

banner() {
    echo ""
    echo "============================================================"
    echo " $1"
    echo "============================================================"
}

header() {
    echo ""
    echo "--- $1"
}

# ---------------------------------------------------------------------------
# Banner.
# ---------------------------------------------------------------------------
banner "Portfolio 5 - Distributed and Cloud Database Exercise
 Student: Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
 Case:    CampusNest - Private Student Accommodation Booking
 Covers:  Study Session 2 (Distributed DB) + Session 3 (Cloud DB)
          + Session 6 (Data Security and Privacy - NDPA 2023)"

# ---------------------------------------------------------------------------
# Step 1 - verify Portfolio 1 ran first.
# ---------------------------------------------------------------------------
header "Step 1: Verify Portfolio 1 schema (9 CampusNest tables) exists"

TABLE_COUNT=$(sudo runuser -u postgres -- psql -d "${DB}" -tAc \
  "SELECT count(*) FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_type   = 'BASE TABLE'
      AND table_name IN ('lodge','room_type','room','tenant','guarantor',
                         'tenancy','rent_instalment','waitlist_entry',
                         'maintenance_ticket');")

echo "Found ${TABLE_COUNT} of 9 expected CampusNest tables."

if [[ "${TABLE_COUNT}" -lt 9 ]]; then
    echo ""
    echo "ERROR: Portfolio 1 schema is not fully loaded."
    echo "       Run portfolio-1-database-design/run_p1.sh first, then re-run this script."
    echo "       (rent_instalment data from P1's bulk_generator.py is required for partitioning.)"
    exit 1
fi

echo "Portfolio 1 schema is present."

# ---------------------------------------------------------------------------
# Step 2 - verify rent_instalment has data and is NOT already partitioned.
# ---------------------------------------------------------------------------
header "Step 2: Verify rent_instalment has data and check partition state"

ROW_COUNT=$(sudo runuser -u postgres -- psql -d "${DB}" -tAc \
  "SELECT count(*) FROM rent_instalment;")

echo "rent_instalment currently has ${ROW_COUNT} rows."

if [[ "${ROW_COUNT}" -eq 0 ]]; then
    echo ""
    echo "ERROR: rent_instalment is empty."
    echo "       Run portfolio-1-database-design/bulk_generator.py first to"
    echo "       generate the 100,000+ rent_instalment rows, then re-run."
    exit 1
fi

IS_PARTITIONED=$(sudo runuser -u postgres -- psql -d "${DB}" -tAc \
  "SELECT EXISTS (
        SELECT 1
          FROM pg_partitioned_table pt
          JOIN pg_class c ON c.oid = pt.partrelid
         WHERE c.relname = 'rent_instalment'
   );")

if [[ "${IS_PARTITIONED}" = "t" ]]; then
    echo ""
    echo "NOTE: rent_instalment is ALREADY partitioned."
    echo "      partition.sql will be SKIPPED to avoid an ALTER TABLE RENAME failure."
    echo "      If you truly need to re-run partition.sql from scratch, drop the"
    echo "      campusnest database and re-run Portfolio 1 first."
    RUN_PARTITION=0
else
    echo "rent_instalment is a flat heap - partition.sql will convert it."
    RUN_PARTITION=1
fi

# ---------------------------------------------------------------------------
# Step 3 - run partition.sql (partitions rent_instalment by academic session).
# ---------------------------------------------------------------------------
banner "Step 3: Run partition.sql - partition rent_instalment by academic session"

if [[ "${RUN_PARTITION}" -eq 1 ]]; then
    if [[ ! -f "${SCRIPT_DIR}/partition.sql" ]]; then
        echo "ERROR: partition.sql not found at ${SCRIPT_DIR}/partition.sql"
        exit 1
    fi
    sudo runuser -u postgres -- psql -d "${DB}" \
        -v ON_ERROR_STOP=1 \
        -f "${SCRIPT_DIR}/partition.sql"
else
    echo "partition.sql skipped (rent_instalment already partitioned)."
fi

# ---------------------------------------------------------------------------
# Step 4 - print the partition list + row distribution (clean capture).
# --------------------------------------------------------------------------
banner "Step 4: Partition list + per-month row distribution (capture for screenshot)"

echo ""
echo "-- List every rent_instalment partition (one per session + 1 default)"
sudo runuser -u postgres -- psql -d "${DB}" -c \
  "SELECT tablename
     FROM pg_tables
    WHERE tablename LIKE 'rent_instalment%'
    ORDER BY tablename;"

echo ""
echo "-- ANALYZE the partitioned parent so pg_class.reltuples is accurate"
sudo runuser -u postgres -- psql -d "${DB}" -c "ANALYZE rent_instalment;"

echo ""
echo "-- Estimated row count per partition (from planner stats after ANALYZE)"
sudo runuser -u postgres -- psql -d "${DB}" -c \
  "SELECT child.relname AS partition,
          child.reltuples::bigint AS approx_rows
     FROM pg_inherits
     JOIN pg_class parent ON parent.oid = pg_inherits.inhparent
     JOIN pg_class child  ON child.oid  = pg_inherits.inhrelid
    WHERE parent.relname = 'rent_instalment'
    ORDER BY child.relname;"

echo ""
echo "-- Row distribution by month (proves rows routed to the right partition)"
sudo runuser -u postgres -- psql -d "${DB}" -c \
  "SELECT date_trunc('month', due_date)::date AS month,
          count(*)                            AS instalments
     FROM rent_instalment
    GROUP BY 1
    ORDER BY 1;"

echo ""
echo "-- Total rows in the partitioned parent (should equal the pre-partition count)"
sudo runuser -u postgres -- psql -d "${DB}" -c \
  "SELECT count(*) AS total_rent_instalment_rows FROM rent_instalment;"

# ---------------------------------------------------------------------------
# Step 5 - build and test the streaming read replica (replication_demo.sh).
# ---------------------------------------------------------------------------
banner "Step 5: Streaming read replica (replication_demo.sh)"
bash "${SCRIPT_DIR}/replication_demo.sh" 2>&1 | tee "${SCRIPT_DIR}/replication_output.log"

banner "Step 6: Read the cloud architecture document"

cat <<'MSG'

 The THIRD centerpiece of Portfolio 5 is the CLOUD ARCHITECTURE
 document that places the CampusNest database in a Nigerian region
 and analyses NDPA 2023 compliance, the CAP theorem trade-offs,
 sync vs async replication, and how the system survives the
 start-of-session rent rush.

 Read it here:

   portfolio-5-distributed-cloud/cloud_architecture.md

 It is grounded in Study Session 2 (distributed DB, CAP, consistency),
 Study Session 3 (cloud database systems), and Study Session 6
 (data security and privacy - NDPA 2023).
MSG

# ---------------------------------------------------------------------------
# Step 7 - what to screenshot + git commit.
# ---------------------------------------------------------------------------
banner "Portfolio 5 complete"
echo " Evidence: p5_output.log (this output) and replication_output.log"
echo " Design write-up: cloud_architecture.md"
