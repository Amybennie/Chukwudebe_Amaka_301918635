#!/usr/bin/env bash
# =============================================================================
# collect_results.sh - gathers the REAL outputs of P1-P5 into my_results.txt
# Run from the repository root after the run-all box:
#     bash collect_results.sh && code my_results.txt
# Then press Ctrl+A, Ctrl+C in my_results.txt and paste the text back.
# Nothing here is invented: it only copies the log files your runs wrote.
# =============================================================================
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
OUT=my_results.txt

clean() {  # drop blank lines and psql command tags so the paste stays short
  grep -v -E '^\s*$|^(CREATE|INSERT|ALTER|DROP|COMMIT|BEGIN|ROLLBACK|ANALYZE|SET|DO|COMMENT|TRUNCATE|SELECT [0-9]+|UPDATE [0-9]+|DELETE [0-9]+)( |$)' "$1"
}
section() {
  local title="$1" file="$2"
  echo
  echo "################################################################"
  echo "## $title  ($file)"
  echo "################################################################"
  if [ -s "$file" ]; then clean "$file"; else echo "(no $file - this part did not run)"; fi
}

{
  echo "MIT 8103 CA - my_results.txt"
  echo "Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)"
  echo "Made    : $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Repo    : $(git remote get-url origin 2>/dev/null | sed 's#https://[^@]*@#https://#' || echo unknown)"
  echo "Machine : $(hostname)  |  $(psql --version 2>/dev/null)  |  mongod $(mongod --version 2>/dev/null | head -1 | awk '{print $3}')"
  echo
  echo "Commits:"
  git log --date=format:'%Y-%m-%d %H:%M' --pretty='  %ad  %s' 2>/dev/null | head -20

  section "P1 Database design"            portfolio-1-database-design/p1_output.log
  section "P2 timings table"              portfolio-2-query-optimisation/p2_timings.md
  section "P2 Query optimisation"         portfolio-2-query-optimisation/p2_output.log
  section "P3 Transactions"               portfolio-3-transactions-concurrency/p3_output.log
  section "P4 NoSQL"                      portfolio-4-nosql/p4_output.log
  section "P5 Distributed and cloud"      portfolio-5-distributed-cloud/p5_output.log
} > "$OUT"

echo "Wrote $OUT ($(wc -l < "$OUT") lines). Open it, press Ctrl+A then Ctrl+C, and paste it back."
