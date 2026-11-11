# Portfolio 2 - Query Processing and Optimisation

**Student:** Amaka Benedicta Chukwudebe
**Matric number:** 2026/A/MIT/0517
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 - Advanced Database Systems
**Academic session:** 2026/2027, First Semester (September Cohort 2026)
**Case study:** CampusNest - Private Student Accommodation Booking
**Database:** `campusnest` (PostgreSQL 16)

---

## Study session covered

**Study Session 4 - Query Optimisation in Database** from the MIT 8103 course notes.

This portfolio demonstrates the three sub-topics of Session 4:

1. **Query execution plans** - we run `EXPLAIN ANALYZE` on each of six analytical queries and read the plan nodes the PostgreSQL 16 planner chose (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join, Nested Loop, Aggregate).
2. **Cost estimation** - we read the `cost=...`, `rows=...`, `actual time=...`, `Rows Removed by Filter`, and `Execution Time:` lines on every plan and compare them before and after adding indexes.
3. **File organisation / indexing** - we add 11 indexes (9 ordinary B-tree indexes on foreign-key columns and date columns, plus 2 partial indexes whose `WHERE` clause exactly matches the query predicates), then re-run the same `EXPLAIN ANALYZE` plans to observe the planner switch from sequential scans to index scans.

---

## Plain-English explanation of what this portfolio does

CampusNest stores more than 50,000 tenancies and more than 100,000 rent instalments (loaded by Portfolio 1). The operations team needs six reports:

1. **Free rooms at a lodge for the next academic session** - which rooms at a lodge have no overlapping tenancy for the next 12 months starting from the first day of next month.
2. **Occupancy percentage per lodge** - for each lodge, what fraction of its rooms currently has an active tenancy covering today.
3. **Rent collected vs outstanding per lodge** - for each lodge, the sum of instalments already paid and the sum still unpaid.
4. **Tenants with overdue instalments** - every tenant whose instalment due date has passed and who has not paid, with the total overdue amount in Naira.
5. **Waitlist length per room type** - how many tenants are queued for each room type at each lodge and how long the longest waiter has been queued.
6. **Average days to fix a maintenance ticket per lodge** - over resolved/closed tickets, the mean elapsed time between `reported_at` and `resolved_at`.

We write the six queries once (`queries.sql`), wrap each in `EXPLAIN ANALYZE` (`explain_before.sql`), create 11 indexes (`indexes.sql`), then re-wrap the same six queries in `EXPLAIN ANALYZE` (`explain_after.sql`). The before/after plan types and execution times go into `before_after_table.md`.

The whole story is: before indexes, the planner sequential-scans the big tables; after indexes, it switches to index scans and bitmap scans and the execution time drops.

---

## Prerequisite: Portfolio 1 must be run first

Portfolio 2 reads from the nine tables that Portfolio 1 creates (`lodge`, `room_type`, `room`, `tenant`, `guarantor`, `tenancy`, `rent_instalment`, `waitlist_entry`, `maintenance_ticket`) and depends on Portfolio 1's bulk generator having loaded at least 10,000 tenancies (the bulk generator targets 50,000+) and 100,000+ rent instalments.

If Portfolio 1 has not been run, `run_p2.sh` aborts in Step 0 with the message:

```
ERROR: only 0 tenancies found in campusnest.tenancy.
       Portfolio 2 needs Portfolio 1's bulk data (>= 10000
       tenancies, ideally 50,000+) ...
       Fix: cd ../portfolio-1-database-design && ./run_p1.sh
```

Run Portfolio 1 first, then re-run Portfolio 2.

---

## Exact Codespaces commands to run this portfolio (in order)

From the repository root:

```bash
# 0. One-time repo setup (do this once per Codespace; safe to re-run)
chmod +x setup.sh
./setup.sh

# 1. Make sure Portfolio 1 has been run first.
cd portfolio-1-database-design
./run_p1.sh
cd ..

# 2. Run Portfolio 2.
cd portfolio-2-query-optimisation
chmod +x run_p2.sh
./run_p2.sh
```

`run_p2.sh` runs five steps in order and prints a clear header before each:

1. **Step 0/0b** - verify P1 data exists (counts tenancies, aborts if < 10,000) and print row counts of all nine tables.
2. **Step 1** - run `queries.sql` and print the six result sets. Screenshot these.
3. **Step 2** - run `explain_before.sql` and print the six `EXPLAIN ANALYZE` plans before any indexes exist. Screenshot each plan.
4. **Step 3** - run `indexes.sql` and create the 11 indexes.
5. **Step 4** - run `explain_after.sql` and print the six `EXPLAIN ANALYZE` plans after the indexes exist. Screenshot each plan.
6. **Step 5** - print the next-actions checklist (paste real results into `before_after_table.md`, what to screenshot for LMS, and the `git commit` command).

If you prefer to run the SQL files individually instead of via the runner, the equivalent commands are:

```bash
sudo runuser -u postgres -- psql -d campusnest -v ON_ERROR_STOP=1 -f queries.sql
sudo runuser -u postgres -- psql -d campusnest -v ON_ERROR_STOP=1 -f explain_before.sql
sudo runuser -u postgres -- psql -d campusnest -v ON_ERROR_STOP=1 -f indexes.sql
sudo runuser -u postgres -- psql -d campusnest -v ON_ERROR_STOP=1 -f explain_after.sql
```

Codespaces conventions baked into every command above:
- `sudo runuser -u postgres -- psql ...` (never `sudo -u postgres`).
- Unix socket `host=/var/run/postgresql` (no TCP, no password).
- Database name is `campusnest` (no typo - the brief confirmed this spelling).

---

## What to screenshot for the LMS submission

After `./run_p2.sh` finishes, capture the following screenshots (one per item, clearly labelled with the query number):

1. **Step 1: six query result sets** (Q1 free rooms, Q2 occupancy %, Q3 rent collected vs outstanding, Q4 overdue instalments, Q5 waitlist length, Q6 avg resolution days). Six screenshots, or one tall screenshot showing all six result sets in order.
2. **Step 2: six BEFORE `EXPLAIN ANALYZE` plans**. One screenshot per plan, labelled "Q1 BEFORE", "Q2 BEFORE", ... "Q6 BEFORE".
3. **Step 3: `indexes.sql` output** showing the 11 `CREATE INDEX` messages and the "All Portfolio 2 indexes created" footer. One screenshot.
4. **Step 4: six AFTER `EXPLAIN ANALYZE` plans**. One screenshot per plan, labelled "Q1 AFTER", "Q2 AFTER", ... "Q6 AFTER".
5. **`before_after_table.md` after you have pasted the real numbers in.** One screenshot of the completed table (or export the markdown file as a PDF).

You do NOT need to screenshot this README or the SQL source files - they are committed to GitHub and the LMS documentation will link to the repository.

---

## Reading the results honestly

`run_p2.sh` first drops every helper index (only primary-key, UNIQUE and
EXCLUDE-constraint indexes stay), runs the BEFORE plans, creates the tuning
indexes, runs the AFTER plans, and writes **`p2_timings.md`** from the two real
logs. Expect:

- **Q7 (one student by matric number)** and **Q4 (overdue instalments)** to
  switch from Seq Scan to index scans; Q7 shows the biggest drop.
- **Q3 (rent per lodge)** to stay a Seq Scan: it adds up every instalment, so
  reading the whole table is the cheapest plan. An index cannot help a query
  that needs every row.
- Small queries (Q1, Q5, Q6) run in about 1-3 ms either way; differences that
  small are timing noise, not a real gain or loss.

Copy the real numbers from `p2_timings.md` into `before_after_table.md`.

## Honesty policy

Every cell in `before_after_table.md` that would contain an EXPLAIN plan, a plan-type name, or an execution time starts as the literal placeholder `[paste real result]`. No plan, no number, no timing has been fabricated. The student replaces each placeholder with the real value produced by `./run_p2.sh` before the LMS submission.

This is the policy set in the repository's top-level `README.md` and required by Section 7 of the CA brief (academic integrity).

---

## The queries (summary - Q7 added: one student's history looked up by matric number)

| # | Query | Output columns | Sorted by |
|---|-------|----------------|-----------|
| Q1 | Rooms free at 'Akoka Heights Lodge' for the next academic session (first day of next month + 12 months) | room_code, room_type_name, annual_rent_ngn, floor | room_code ASC |
| Q2 | Occupancy percentage per lodge | lodge_name, nearest_school, total_rooms, occupied_now, occupancy_pct | lodge_name ASC |
| Q3 | Rent collected vs outstanding per lodge | lodge_name, collected_ngn, outstanding_ngn, total_billed_ngn | lodge_name ASC |
| Q4 | Tenants with overdue instalments (due_date < today AND paid_at IS NULL) | tenant_full_name, nearest_school, lodge_name, overdue_amount_ngn, count_overdue_instalments | overdue_amount_ngn DESC |
| Q5 | Waitlist length per room type | lodge_name, room_type_name, annual_rent_ngn, waitlist_count, longest_wait_days | waitlist_count DESC |
| Q6 | Average days to fix a maintenance ticket per lodge (resolved_at IS NOT NULL) | lodge_name, total_tickets, resolved_tickets, avg_resolution_days | lodge_name ASC |

> If Q1 returns zero rows, the lodge name `Akoka Heights Lodge` is not present in your Portfolio 1 data. Run `SELECT name FROM lodge ORDER BY name;` and substitute a real name in `queries.sql` (and in `explain_before.sql` and `explain_after.sql` to keep the three files in sync).

---

## The indexes created by `indexes.sql` (12, including `idx_tenant_matric` for Q7)

| # | Index name | Table (columns) | Targets | Type |
|---|------------|-----------------|---------|------|
| 1 | `idx_room_lodge_id` | `room (lodge_id)` | Q1, Q2 | B-tree |
| 2 | `idx_room_room_type_id` | `room (room_type_id)` | Q1 | B-tree |
| 3 | `idx_tenancy_room_id` | `tenancy (room_id)` | Q1 NOT EXISTS | B-tree |
| 4 | `idx_tenancy_tenant_id` | `tenancy (tenant_id)` | Q4 | B-tree |
| 5 | `idx_tenancy_start_end` | `tenancy (start_date, end_date)` | Q1 daterange overlap | B-tree composite |
| 6 | `idx_rent_instalment_tenancy_id` | `rent_instalment (tenancy_id)` | Q3, Q4 | B-tree |
| 7 | `idx_rent_instalment_overdue` | `rent_instalment (due_date) WHERE paid_at IS NULL` | Q4 overdue predicate | Partial B-tree |
| 8 | `idx_rent_instalment_paid_at` | `rent_instalment (paid_at)` | Q3 paid/unpaid split | B-tree |
| 9 | `idx_waitlist_room_type_id` | `waitlist_entry (room_type_id)` | Q5 | B-tree |
| 10 | `idx_maintenance_lodge_resolved` | `maintenance_ticket (lodge_id) WHERE resolved_at IS NOT NULL` | Q6 | Partial B-tree |
| 11 | `idx_maintenance_resolved_at` | `maintenance_ticket (resolved_at)` | Q6 | B-tree |

Notes:
- PostgreSQL already auto-creates B-tree indexes for every `PRIMARY KEY` and `UNIQUE` constraint, so those columns are not re-indexed here.
- PostgreSQL does **not** auto-create indexes on `FOREIGN KEY` columns. Most indexes above (1, 2, 3, 4, 6, 9) fill in exactly those FK-side columns.
- The two partial indexes (7, 10) match the `WHERE paid_at IS NULL` and `WHERE resolved_at IS NOT NULL` predicates of Q4 and Q6 respectively, so the planner can seek the relevant rows directly.
- `CREATE INDEX IF NOT EXISTS` makes `indexes.sql` idempotent.
- PostgreSQL runs an automatic `ANALYZE` on each affected table after every `CREATE INDEX`, so the AFTER plans in `explain_after.sql` see fresh planner statistics without a separate `ANALYZE` step.

---

## File inventory

| File | Purpose |
|------|---------|
| `README.md` | This file. Study session covered, plain-English summary, prerequisites, exact Codespaces commands, what to screenshot, git commit, file inventory. |
| `queries.sql` | The six analytical queries, each preceded by a `\echo` plain-English description. Run by `run_p2.sh` Step 1. |
| `explain_before.sql` | The same six queries wrapped in `EXPLAIN ANALYZE`, executed BEFORE any indexes exist. Run by `run_p2.sh` Step 2. |
| `indexes.sql` | 11 `CREATE INDEX IF NOT EXISTS` statements, each preceded by a `\echo` explaining which query it targets and why. Run by `run_p2.sh` Step 3. |
| `explain_after.sql` | The same six queries wrapped in `EXPLAIN ANALYZE`, executed AFTER the indexes exist. Run by `run_p2.sh` Step 4. |
| `before_after_table.md` | Markdown before/after comparison table with `[paste real result]` placeholders for plan type and execution time of each query, plus a glossary of EXPLAIN vocabulary (Seq Scan, Index Scan, Index Cond, Bitmap Heap Scan, loops, planning vs execution time). The student pastes real values after running `run_p2.sh`. |
| `run_p2.sh` | Executable bash runner. Verifies P1 data exists, runs the 6 queries, runs BEFORE EXPLAIN, creates the indexes, runs AFTER EXPLAIN, prints the next-actions checklist. Uses `sudo runuser -u postgres -- psql -d campusnest -v ON_ERROR_STOP=1` throughout. |

---

## Exact git commit command

After running `./run_p2.sh` and pasting the real results into `before_after_table.md`, commit from the repository root:

```bash
cd /workspaces/<your-repo>
git add portfolio-2-query-optimisation
git commit -m 'Portfolio 2: 6 queries, EXPLAIN ANALYZE before/after 11 indexes'
```

If you also need to push to your private GitHub remote:

```bash
git push origin main
```

(Use whatever branch name matches your repository - `main`, `master`, or a feature branch.)

---

## AI use declaration (filled in by student after running)

This will be completed in the final documentation file
`Chukwudebe_Amaka_2026-A-MIT-0517_Documentation.pdf`, produced after all five
portfolios have been run and the real results pasted in. It will state:
1. The AI tool used.
2. What the AI tool was used for.
3. How the output was reviewed, corrected, tested, or verified by the student.
