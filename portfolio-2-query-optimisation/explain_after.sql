-- =====================================================================
-- MIT 8103 Advanced Database Systems - Portfolio 2
-- Query Processing and Optimisation
-- Student : Amaka Benedicta Chukwudebe  (2026/A/MIT/0517)
-- Case    : CampusNest - Private Student Accommodation Booking
-- File    : explain_after.sql
-- Purpose : Identical to explain_before.sql, but executed AFTER the
--           indexes in indexes.sql have been created. The query text is
--           byte-for-byte the same so the BEFORE and AFTER plans are
--           directly comparable.
--
--           Screenshot every plan below for the LMS submission and
--           paste the plan text into before_after_table.md under the
--           'After' columns.
--
--           Where the student has not yet run this script, the markdown
--           table uses the literal placeholder [paste real result] -
--           no plan is fabricated.
-- =====================================================================

\echo ===================================================================
\echo MIT 8103 Advanced Database Systems - Portfolio 2
\echo EXPLAIN ANALYZE - AFTER INDEXES
\echo Student: Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
\echo ===================================================================
\echo
\echo Each block below runs EXPLAIN ANALYZE on one of the seven queries,
\echo AFTER the indexes in indexes.sql were created.
\echo Look for: Index Scan and Bitmap Index Scan nodes replacing the
\echo Seq Scan nodes you saw before, lower execution time in ms, and
\echo lower actual rows removed by filters.
\echo
\echo Paste each plan into before_after_table.md under the 'After'
\echo columns, next to the matching BEFORE plan from explain_before.sql.
\echo

-- =====================================================================
-- Q1 EXPLAIN ANALYZE - AFTER INDEXES
-- =====================================================================
\echo ===== Q1: free rooms - AFTER INDEXES =====

EXPLAIN ANALYZE
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
-- Q2 EXPLAIN ANALYZE - AFTER INDEXES
-- =====================================================================
\echo ===== Q2: occupancy pct - AFTER INDEXES =====

EXPLAIN ANALYZE
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
ORDER BY l.name;

\echo
-- =====================================================================
-- Q3 EXPLAIN ANALYZE - AFTER INDEXES
-- =====================================================================
\echo ===== Q3: rent collected vs outstanding - AFTER INDEXES =====

EXPLAIN ANALYZE
SELECT l.name AS lodge_name,
       COALESCE(SUM(ri.amount_ngn) FILTER (WHERE ri.paid_at IS NOT NULL), 0)::numeric(14,2) AS collected_ngn,
       COALESCE(SUM(ri.amount_ngn) FILTER (WHERE ri.paid_at IS NULL),       0)::numeric(14,2) AS outstanding_ngn,
       COALESCE(SUM(ri.amount_ngn),                                          0)::numeric(14,2) AS total_billed_ngn
FROM   lodge l
LEFT JOIN room            r  ON r.lodge_id    = l.lodge_id
LEFT JOIN tenancy         t  ON t.room_id     = r.room_id
LEFT JOIN rent_instalment ri ON ri.tenancy_id = t.tenancy_id
GROUP BY l.lodge_id, l.name
ORDER BY l.name;

\echo
-- =====================================================================
-- Q4 EXPLAIN ANALYZE - AFTER INDEXES
-- =====================================================================
\echo ===== Q4: tenants with overdue instalments - AFTER INDEXES =====

EXPLAIN ANALYZE
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
ORDER BY overdue_amount_ngn DESC;

\echo
-- =====================================================================
-- Q5 EXPLAIN ANALYZE - AFTER INDEXES
-- =====================================================================
\echo ===== Q5: waitlist length per room type - AFTER INDEXES =====

EXPLAIN ANALYZE
SELECT l.name               AS lodge_name,
       rt.name              AS room_type_name,
       rt.annual_rent_ngn,
       COUNT(w.waitlist_id)                                   AS waitlist_count,
       COALESCE(MAX(CURRENT_DATE - w.joined_at::date), 0)     AS longest_wait_days
FROM   room_type rt
JOIN   lodge          l  ON l.lodge_id       = rt.lodge_id
LEFT JOIN waitlist_entry w ON w.room_type_id = rt.room_type_id
GROUP BY rt.room_type_id, l.name, rt.name, rt.annual_rent_ngn
ORDER BY waitlist_count DESC, l.name, rt.name;

\echo
-- =====================================================================
-- Q6 EXPLAIN ANALYZE - AFTER INDEXES
-- =====================================================================
\echo ===== Q6: avg days to fix maintenance ticket - AFTER INDEXES =====

EXPLAIN ANALYZE
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
ORDER BY l.name;

\echo
-- =====================================================================
-- Q7 EXPLAIN ANALYZE - AFTER INDEXES
-- =====================================================================
\echo ===== Q7: student history by matric - AFTER INDEXES =====

EXPLAIN ANALYZE
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
\echo ===== End of EXPLAIN ANALYZE AFTER INDEXES =====
\echo Compare each plan with the matching BEFORE plan from
\echo explain_before.sql and paste both into before_after_table.md.
