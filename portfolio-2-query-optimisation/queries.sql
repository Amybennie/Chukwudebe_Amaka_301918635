-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2
-- Query Processing and Optimisation
-- Student : Amaka Benedicta Chukwudebe  (2026/A/MIT/0517)
-- Case    : CampusNest - Private Student Accommodation Booking
-- File    : queries.sql
-- Purpose : Six production-style analytical queries against the CampusNest
--           relational schema built by Portfolio 1. The same six query
--           blocks are reused (verbatim) inside explain_before.sql and
--           explain_after.sql, wrapped in EXPLAIN ANALYZE, so the
--           BEFORE / AFTER plans are directly comparable.
-- Notes   : - All date logic is relative to CURRENT_DATE, so the output
--             never expires and stays valid across cohorts.
--           - Naira amounts are stored as NUMERIC(12,2). The brief forbids
--             the unicode naira sign in .sql files; the column suffix
--             _ngn is the convention instead.
--           - Q1 uses a literal lodge name 'Akoka Heights Lodge' as the
--             worked example. If your Portfolio 1 seeded lodges under
--             different names, run:  SELECT name FROM lodge ORDER BY name;
--             and substitute one of those names for the WHERE clause.
-- =====================================================================

\echo ===================================================================
\echo MIT 8103 Advanced Database Systems - Portfolio 2
\echo Query Processing and Optimisation
\echo Student: Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
\echo Case study: CampusNest - Private Student Accommodation Booking
\echo ===================================================================
\echo
\echo This file contains the 7 queries for Portfolio 2.
\echo Each query is preceded by a plain-English description of what it
\echo answers for the CampusNest operations team.
\echo
\echo If Q1 returns zero rows, the lodge name 'Akoka Heights Lodge' is
\echo not present in your Portfolio 1 data. Run:  SELECT name FROM lodge;
\echo and substitute a real name in the WHERE clause below.
\echo

-- =====================================================================
-- Q1. Rooms free at a lodge for the next academic session
--     Plain English: For the lodge named 'Akoka Heights Lodge', list
--     every room that has NO tenancy overlapping the next academic
--     session. The next session runs from the first day of next month
--     for 12 months. A room is 'free' if no active or ended tenancy
--     covers any day of that window. Cancelled tenancies are ignored.
--     Two half-open ranges [a1,a2) and [b1,b2) overlap iff
--     a1 < b2 AND a2 > b1, which is the predicate used below.
-- =====================================================================
\echo ===== Q1: Rooms free at a lodge for the next academic session =====
\echo Plain English: List rooms at 'Akoka Heights Lodge' that have no
\echo tenancy overlapping the next academic session (first day of next
\echo month through +12 months). Cancelled tenancies do not block a room.
\echo

WITH session_range AS (
    SELECT
        (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::date   AS session_start,
        (date_trunc('month', CURRENT_DATE) + INTERVAL '13 months')::date AS session_end
)
SELECT r.room_code,
       rt.name            AS room_type_name,
       rt.annual_rent_ngn,
       r.floor
FROM   room r
JOIN   lodge      l  ON l.lodge_id      = r.lodge_id
JOIN   room_type  rt ON rt.room_type_id = r.room_type_id
CROSS JOIN session_range sr
WHERE  l.name = 'Akoka Heights Lodge'
  AND NOT EXISTS (
        SELECT 1
        FROM   tenancy t
        WHERE  t.room_id    = r.room_id
          AND  t.status    <> 'cancelled'
          AND  t.start_date <  sr.session_end
          AND  t.end_date   >  sr.session_start
      )
ORDER BY r.room_code;

\echo
-- =====================================================================
-- Q2. Occupancy percentage per lodge
--     Plain English: For each lodge, count the rooms that currently
--     have an active tenancy overlapping today, divide by the total
--     number of rooms in that lodge, and multiply by 100. The EXCLUDE
--     constraint on tenancy guarantees a room can have at most one
--     active tenancy covering today, so the LEFT JOIN below does not
--     double-count rooms.
-- =====================================================================
\echo ===== Q2: Occupancy percentage per lodge =====
\echo Plain English: For each lodge, divide the number of rooms with an
\echo active tenancy covering today by the total rooms, then multiply by
\echo 100. One row per lodge, sorted by lodge name.
\echo

SELECT l.name            AS lodge_name,
       l.nearest_school,
       COUNT(r.room_id)  AS total_rooms,
       COUNT(t.room_id)  AS occupied_now,
       ROUND(
           CASE WHEN COUNT(r.room_id) = 0 THEN 0
                ELSE (COUNT(t.room_id)::numeric / COUNT(r.room_id)::numeric) * 100
           END, 2
       )                 AS occupancy_pct
FROM   lodge l
LEFT JOIN room    r ON r.lodge_id = l.lodge_id
LEFT JOIN tenancy t ON t.room_id  = r.room_id
                    AND t.status  = 'active'
                    AND t.start_date <= CURRENT_DATE
                    AND t.end_date    >  CURRENT_DATE
GROUP BY l.lodge_id, l.name, l.nearest_school
ORDER BY occupancy_pct DESC, l.name
LIMIT 15;   -- 15 fullest lodges shown (100 lodges in total)

\echo
-- =====================================================================
-- Q3. Rent collected vs outstanding per lodge
--     Plain English: For each lodge, sum every rent instalment whose
--     paid_at is NOT NULL (collected) and every instalment whose paid_at
--     IS NULL (outstanding), plus the grand total billed. The join path
--     is lodge -> room -> tenancy -> rent_instalment so each instalment
--     is attributed to the lodge whose room the tenant occupies.
-- =====================================================================
\echo ===== Q3: Rent collected vs outstanding per lodge =====
\echo Plain English: For each lodge, sum rent instalments already paid
\echo (paid_at IS NOT NULL) and still outstanding (paid_at IS NULL), plus
\echo the total billed. Amounts are in Naira, rounded to 2 decimals.
\echo

SELECT l.name AS lodge_name,
       COALESCE(SUM(ri.amount_ngn) FILTER (WHERE ri.paid_at IS NOT NULL), 0)::numeric(14,2) AS collected_ngn,
       COALESCE(SUM(ri.amount_ngn) FILTER (WHERE ri.paid_at IS NULL),       0)::numeric(14,2) AS outstanding_ngn,
       COALESCE(SUM(ri.amount_ngn),                                          0)::numeric(14,2) AS total_billed_ngn
FROM   lodge l
LEFT JOIN room            r  ON r.lodge_id    = l.lodge_id
LEFT JOIN tenancy         t  ON t.room_id     = r.room_id
LEFT JOIN rent_instalment ri ON ri.tenancy_id = t.tenancy_id
GROUP BY l.lodge_id, l.name
ORDER BY outstanding_ngn DESC
LIMIT 15;   -- 15 lodges with the most rent outstanding

\echo
-- =====================================================================
-- Q4. Tenants with overdue instalments
--     Plain English: An instalment is overdue if its due_date is in the
--     past and it has not been paid (paid_at IS NULL). For each tenant
--     who owes at least one overdue instalment, show their name, nearest
--     school, the lodge they currently rent in, the total amount overdue
--     in Naira, and how many instalments are overdue. Highest debt first.
-- =====================================================================
\echo ===== Q4: Tenants with overdue instalments =====
\echo Plain English: For each tenant who has at least one instalment
\echo whose due_date has passed and is still unpaid, show their name,
\echo nearest school, lodge, total overdue amount (Naira), and the count
\echo of overdue instalments. Ordered by overdue amount descending.
\echo

SELECT t.full_name   AS tenant_full_name,
       t.nearest_school,
       l.name        AS lodge_name,
       SUM(ri.amount_ngn)::numeric(14,2) AS overdue_amount_ngn,
       COUNT(*)                          AS count_overdue_instalments
FROM   rent_instalment ri
JOIN   tenancy tn ON tn.tenancy_id = ri.tenancy_id
JOIN   room     r  ON r.room_id    = tn.room_id
JOIN   lodge    l  ON l.lodge_id    = r.lodge_id
JOIN   tenant   t  ON t.tenant_id   = tn.tenant_id
WHERE  ri.due_date < CURRENT_DATE
  AND  ri.paid_at IS NULL
GROUP BY t.tenant_id, t.full_name, t.nearest_school, l.name
ORDER BY overdue_amount_ngn DESC
LIMIT 15;   -- top 15 shown; EXPLAIN in explain_*.sql measures the full list

\echo
-- =====================================================================
-- Q5. Waitlist length per room type
--     Plain English: For every room type at every lodge, show how many
--     tenants are queued on the waitlist and how long the longest-
--     waiting tenant has been in the queue, expressed in whole days.
--     Room types with the longest queues appear first. Room types with
--     no waitlist still appear with waitlist_count = 0 and
--     longest_wait_days = 0.
-- =====================================================================
\echo ===== Q5: Waitlist length per room type =====
\echo Plain English: For each room type at each lodge, count the
\echo waitlist entries and report how many days the longest-waiting
\echo tenant has been queued. Busiest queues first.
\echo

SELECT l.name               AS lodge_name,
       rt.name              AS room_type_name,
       rt.annual_rent_ngn,
       COUNT(w.waitlist_id)                                   AS waitlist_count,
       COALESCE(MAX(CURRENT_DATE - w.joined_at::date), 0)     AS longest_wait_days
FROM   room_type rt
JOIN   lodge          l  ON l.lodge_id       = rt.lodge_id
LEFT JOIN waitlist_entry w ON w.room_type_id = rt.room_type_id
GROUP BY rt.room_type_id, l.name, rt.name, rt.annual_rent_ngn
ORDER BY waitlist_count DESC, l.name, rt.name
LIMIT 15;   -- busiest 15 queues shown

\echo
-- =====================================================================
-- Q6. Average days to fix a maintenance ticket per lodge
--     Plain English: For each lodge, count all maintenance tickets and
--     the subset that has been resolved or closed (resolved_at is set),
--     then compute the average number of days between reported_at and
--     resolved_at over only those resolved tickets. AVG ignores NULLs
--     automatically, so unresolved tickets do not drag the average down.
-- =====================================================================
\echo ===== Q6: Average days to fix a maintenance ticket per lodge =====
\echo Plain English: For each lodge, count total tickets, the subset that
\echo has been resolved (resolved_at IS NOT NULL), and the average number
\echo of days between reported_at and resolved_at over only resolved
\echo tickets. Sorted by lodge name.
\echo

SELECT l.name AS lodge_name,
       COUNT(m.ticket_id)                                          AS total_tickets,
       COUNT(m.ticket_id) FILTER (WHERE m.resolved_at IS NOT NULL) AS resolved_tickets,
       ROUND(
           AVG(EXTRACT(EPOCH FROM (m.resolved_at - m.reported_at)) / 86400.0)::numeric,
           2
       )                                                           AS avg_resolution_days
FROM   lodge l
LEFT JOIN maintenance_ticket m ON m.lodge_id = l.lodge_id
GROUP BY l.lodge_id, l.name
ORDER BY avg_resolution_days DESC NULLS LAST
LIMIT 15;   -- 15 slowest lodges at fixing tickets

\echo
\echo ===== Q7: student history by matric number =====
\echo Plain English: the front desk types a student matric number and sees
\echo every tenancy that student has held and how much has been paid on each.
\echo
SELECT t.full_name, t.student_matric, l.name AS lodge_name, r.room_code,
       tn.start_date, tn.end_date, tn.status,
       COUNT(ri.instalment_id)                                   AS instalments,
       COALESCE(SUM(ri.amount_ngn) FILTER (WHERE ri.status = 'paid'), 0)::numeric(14,2) AS paid_ngn
FROM   tenant t
JOIN   tenancy tn ON tn.tenant_id = t.tenant_id
JOIN   room    r  ON r.room_id    = tn.room_id
JOIN   lodge   l  ON l.lodge_id   = r.lodge_id
LEFT JOIN rent_instalment ri ON ri.tenancy_id = tn.tenancy_id
WHERE  t.student_matric = (SELECT student_matric FROM tenant WHERE tenant_id =
                           (SELECT tenant_id FROM tenancy WHERE tenancy_id = 20002))
GROUP BY t.tenant_id, t.full_name, t.student_matric, l.name, r.room_code, tn.tenancy_id, tn.start_date, tn.end_date, tn.status
ORDER BY tn.start_date;
\echo
\echo ===== End of Portfolio 2 queries =====
\echo If you are reading this in a screenshot, the six query result sets
\echo above are the 'business output' to attach to your LMS submission.
