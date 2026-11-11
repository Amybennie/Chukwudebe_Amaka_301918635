# Portfolio 2 - Before / After comparison

**Student:** Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
**Case study:** CampusNest - Private Student Accommodation Booking
**Database:** `campusnest` (PostgreSQL 16)

## Where the numbers come from

`run_p2.sh` builds `p2_timings.md` automatically from `explain_before.log` and
`explain_after.log`, which hold the real EXPLAIN ANALYZE output of your own run.
Copy the times from `p2_timings.md` into the table below. Do not invent numbers.

- **BEFORE** = only the indexes behind primary keys, UNIQUE and EXCLUDE
  constraints (the script drops every other index first, then runs ANALYZE).
- **AFTER** = the tuning indexes in `indexes.sql`, then ANALYZE.

## Comparison table

| Query | Before: main scan | Before ms | After: main scan | After ms | What happened and why |
|---|---|---|---|---|---|
| Q1 free beds at Akoka Heights Lodge next session | [paste from p2_timings.md] | | | | Small lodge; the exclusion constraint's GiST index already serves the NOT EXISTS probe, so both runs are fast. |
| Q2 occupancy % per lodge | | | | | `idx_tenancy_start_end` can replace the Seq Scan on tenancy, but about a quarter of all tenancies are current, so the gain is small. |
| Q3 rent collected vs outstanding per lodge | | | | | Expected to stay a Seq Scan: it adds up every instalment, so reading the whole table is the cheapest plan. |
| Q4 tenants with overdue instalments | | | | | The partial index `idx_rent_instalment_overdue` (unpaid rows only) replaces the Seq Scan on rent_instalment. |
| Q5 waitlist length per room type | | | | | Tiny table (a few hundred rows); a Seq Scan is the right plan either way. |
| Q6 average days to fix a ticket per lodge | | | | | Aggregates every ticket; stays a Seq Scan. |
| Q7 one student's history by matric number | | | | | The headline gain: Seq Scans on tenant, tenancy and rent_instalment become Index Scans (`idx_tenant_matric`, `idx_tenancy_tenant_id`, `idx_rent_instalment_tenancy_id`). |

## Honest conclusion (fill in with your real numbers)

Indexes help queries that pick out a few rows (Q4, Q7). They do not help
reports that must read every row (Q3, Q6), and the planner correctly keeps a
Seq Scan there. Times of 1-3 ms are within timing noise between runs.
