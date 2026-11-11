-- =============================================================================
-- seed.sql - small realistic seed data for CampusNest (Portfolio 1)
-- -----------------------------------------------------------------------------
-- Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
-- Course  : MIT 8103 Advanced Database Systems
-- -----------------------------------------------------------------------------
-- Loads a small but realistic dataset on top of schema.sql:
--   * 4 lodges (one per school)
--   * 12 room types (3 per lodge: single, shared_2, shared_4)
--   * 24 rooms (6 per lodge, 2 per room type)
--   * 12 tenants (realistic Nigerian names across Yoruba / Igbo / Hausa)
--   * 12 guarantors (one per tenant)
--   * 8 tenancies (no overlaps; all in the current academic session)
--   * 18 rent instalments (1-3 per tenancy, summing exactly to annual rent)
--   * 2 waitlist entries for a sold-out UNILAG single room type
--   * 4 maintenance tickets (plumbing, electrical, furniture, pest_control)
--
-- All inserts sit inside one BEGIN/COMMIT transaction so the DEFERRABLE
-- INITIALLY DEFERRED guarantor trigger (trg_require_guarantor) only fires once
-- at COMMIT, by which point every tenant already has a guarantor.
--
-- Currency: Naira (NGN). Amounts are written as plain numbers in .sql
-- (e.g. 850000 = 850,000 naira). The unicode naira sign is not used here.
--
-- Run with:
--   sudo runuser -u postgres -- psql -d campusnest -v ON_ERROR_STOP=1 -f seed.sql
-- =============================================================================

BEGIN;

-- 1. Lodges (one per school). -----------------------------------------------
INSERT INTO lodge (name, nearest_school, address_line, city, state) VALUES
    ('Akoka Heights Lodge',   'UNILAG',   '12 Akoka Road',          'Akoka',   'Lagos'),
    ('Yaba Tech Suites',      'YABATECH', '5 Herbert Macaulay Way', 'Yaba',    'Lagos'),
    ('Ojo Gardens Residence', 'LASU',     '8 Iba Road',             'Ojo',     'Lagos'),
    ('Nsukka Scholars Lodge', 'UNN',      '15 Margaret Ekpo Street','Nsukka',  'Enugu');

-- 2. Room types (3 per lodge = 12 total). -----------------------------------
--    Rent ranges (naira, annual, per bed):
--      UNILAG   (Akoka, baseline): single 850,000 / shared_2 450,000 / shared_4 350,000
--      YABATECH (Yaba):            single 800,000 / shared_2 420,000 / shared_4 320,000
--      LASU     (Ojo, ~15% cheaper): single 720,000 / shared_2 380,000 / shared_4 300,000
--      UNN      (Nsukka, ~30% cheaper): single 595,000 / shared_2 315,000 / shared_4 245,000
INSERT INTO room_type (lodge_id, name, annual_rent_ngn, capacity) VALUES
    (1, 'single',   850000.00, 1),
    (1, 'shared_2', 450000.00, 2),
    (1, 'shared_4', 350000.00, 4),
    (2, 'single',   800000.00, 1),
    (2, 'shared_2', 420000.00, 2),
    (2, 'shared_4', 320000.00, 4),
    (3, 'single',   720000.00, 1),
    (3, 'shared_2', 380000.00, 2),
    (3, 'shared_4', 300000.00, 4),
    (4, 'single',   595000.00, 1),
    (4, 'shared_2', 315000.00, 2),
    (4, 'shared_4', 245000.00, 4);

-- 3. Rooms (6 per lodge = 24 total, 2 per room type). -----------------------
--    room_code convention: <lodge-initials>-<type>-<floor><seq>, e.g. AH-S-101.
INSERT INTO room (lodge_id, room_type_id, room_code, floor) VALUES
    -- Akoka Heights (UNILAG): room_type_id 1=single, 2=shared_2, 3=shared_4
    (1, 1, 'AH-S-101',  1), (1, 1, 'AH-S-102',  1),
    (1, 2, 'AH-S2-201', 2), (1, 2, 'AH-S2-202', 2),
    (1, 3, 'AH-S4-301', 3), (1, 3, 'AH-S4-302', 3),
    -- Yaba Tech Suites (YABATECH): room_type_id 4, 5, 6
    (2, 4, 'YT-S-101',  1), (2, 4, 'YT-S-102',  1),
    (2, 5, 'YT-S2-201', 2), (2, 5, 'YT-S2-202', 2),
    (2, 6, 'YT-S4-301', 3), (2, 6, 'YT-S4-302', 3),
    -- Ojo Gardens (LASU): room_type_id 7, 8, 9
    (3, 7, 'OG-S-101',  1), (3, 7, 'OG-S-102',  1),
    (3, 8, 'OG-S2-201', 2), (3, 8, 'OG-S2-202', 2),
    (3, 9, 'OG-S4-301', 3), (3, 9, 'OG-S4-302', 3),
    -- Nsukka Scholars (UNN): room_type_id 10, 11, 12
    (4, 10, 'NS-S-101',  1), (4, 10, 'NS-S-102',  1),
    (4, 11, 'NS-S2-201', 2), (4, 11, 'NS-S2-202', 2),
    (4, 12, 'NS-S4-301', 3), (4, 12, 'NS-S4-302', 3);

-- 4. Tenants (12, distributed across the four schools). --------------------
INSERT INTO tenant (full_name, email, phone, student_matric, nearest_school) VALUES
    ('Adeola Okafor',       'adeola.okafor@campusnest.example',      '+234 803 111 0001', 'MIV/2026/0001', 'UNILAG'),
    ('Chioma Adeyemi',      'chioma.adeyemi@campusnest.example',     '+234 803 222 0002', 'MIV/2026/0002', 'UNILAG'),
    ('Tunde Bakare',        'tunde.bakare@campusnest.example',       '+234 805 333 0003', 'MIV/2026/0003', 'YABATECH'),
    ('Funke Adewale',       'funke.adewale@campusnest.example',      '+234 805 444 0004', 'MIV/2026/0004', 'YABATECH'),
    ('Ngozi Eze',           'ngozi.eze@campusnest.example',          '+234 806 555 0005', 'MIV/2026/0005', 'LASU'),
    ('Emeka Obi',           'emeka.obi@campusnest.example',          '+234 806 666 0006', 'MIV/2026/0006', 'LASU'),
    ('Aisha Bello',         'aisha.bello@campusnest.example',        '+234 807 777 0007', 'MIV/2026/0007', 'UNN'),
    ('Ibrahim Sani',        'ibrahim.sani@campusnest.example',       '+234 807 888 0008', 'MIV/2026/0008', 'UNN'),
    ('Chidinma Nwosu',      'chidinma.nwosu@campusnest.example',     '+234 803 999 0009', 'MIV/2026/0009', 'UNILAG'),
    ('Ifeanyi Okeke',       'ifeanyi.okeke@campusnest.example',      '+234 805 101 0010', 'MIV/2026/0010', 'UNILAG'),
    ('Fatima Abdullahi',    'fatima.abdullahi@campusnest.example',   '+234 806 202 0011', 'MIV/2026/0011', 'YABATECH'),
    ('Musa Danjuma',        'musa.danjuma@campusnest.example',       '+234 807 303 0012', 'MIV/2026/0012', 'LASU');

-- 5. Guarantors (one per tenant). -------------------------------------------
--    Same transaction as tenants so the deferred trg_require_guarantor fires
--    only at COMMIT and finds every tenant already covered.
INSERT INTO guarantor (tenant_id, full_name, phone, email, relationship, home_address) VALUES
    (1, 'Biodun Okafor',     '+234 803 911 1001', 'biodun.okafor@example.com',     'Parent',    '14 Akoka Road, Akoka, Lagos'),
    (2, 'Yetunde Adeyemi',   '+234 803 922 2002', 'yetunde.adeyemi@example.com',   'Parent',    '7 Market Street, Yaba, Lagos'),
    (3, 'Seyi Bakare',       '+234 805 933 3003', 'seyi.bakare@example.com',       'Guardian',  '22 Herbert Macaulay Way, Yaba, Lagos'),
    (4, 'Temitope Adewale',  '+234 805 944 4004', 'temitope.adewale@example.com',  'Parent',    '3 Bode Thomas, Surulere, Lagos'),
    (5, 'Nnamdi Eze',        '+234 806 955 5005', 'nnamdi.eze@example.com',        'Parent',    '18 Iba Road, Ojo, Lagos'),
    (6, 'Chiwendu Obi',      '+234 806 966 6006', 'chiwendu.obi@example.com',      'Aunt',      '9 Ago Palace Way, Okota, Lagos'),
    (7, 'Halima Bello',      '+234 807 977 7007', 'halima.bello@example.com',      'Parent',    '31 Wuse 2, Abuja'),
    (8, 'Yusuf Sani',        '+234 807 988 8008', 'yusuf.sani@example.com',        'Uncle',     '5 Garki Area 3, Abuja'),
    (9, 'Obinna Nwosu',      '+234 803 999 9009', 'obinna.nwosu@example.com',      'Sibling',   '12 Independence Layout, Enugu'),
    (10,'Amaka Okeke',       '+234 805 010 1010', 'amaka.okeke@example.com',       'Parent',    '4 Abakpa Nike, Enugu'),
    (11,'Sani Abdullahi',    '+234 806 020 1111', 'sani.abdullahi@example.com',    'Parent',    '27 Tudun Wada, Kaduna'),
    (12,'Mohammed Danjuma',  '+234 807 030 1212', 'mohammed.danjuma@example.com',  'Uncle',     '8 Rigasa, Kaduna');

-- 6. Session window (temp table so the instalment inserts below can reuse it).
CREATE TEMP TABLE p1_session AS
SELECT date_trunc('month', CURRENT_DATE)::date                          AS session_start,
       (date_trunc('month', CURRENT_DATE) + interval '12 months')::date AS session_end;

-- 7. Tenancies (8, no overlaps: distinct rooms, distinct tenants, same window).
INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn, status)
SELECT
    r.room_id,
    t.tenant_id,
    s.session_start,
    s.session_end,
    rt.annual_rent_ngn,
    'active'
FROM p1_session s,
 (VALUES
    (1, 1, 1), (2, 7, 3), (3, 15,5), (4, 23,7), (5, 3, 2), (6, 11,4), (7, 14,6), (8, 21,8)
 ) AS v(ord, room_no, tenant_no)
JOIN room  r  ON r.room_id = v.room_no
JOIN tenant t ON t.tenant_id = v.tenant_no
JOIN room_type rt ON rt.room_type_id = r.room_type_id
ORDER BY v.ord;   -- fixed order, so tenancy_id 1..8 match the instalment blocks below

-- 8. Rent instalments (18 total).
--    Each tenancy gets 1-3 instalments summing EXACTLY to annual_rent_ngn.
--    Instalments for one tenancy are inserted in a single statement so the
--    trg_instalment_sum BEFORE INSERT trigger sees them in ascending order.
--    Past dues (due_date <= today) are 'paid' with a paid_at; future are 'pending'.
--
--    Tenancy -> annual_rent -> split:
--      1 -> 850,000 -> 425,000 + 425,000               (2 instalments)
--      2 -> 800,000 -> 400,000 + 400,000               (2)
--      3 -> 380,000 -> 130,000 + 130,000 + 120,000     (3)
--      4 -> 245,000 -> 245,000                          (1)
--      5 -> 450,000 -> 150,000 + 150,000 + 150,000     (3)
--      6 -> 320,000 -> 120,000 + 100,000 + 100,000     (3)
--      7 -> 720,000 -> 360,000 + 360,000               (2)
--      8 -> 315,000 -> 157,500 + 157,500               (2)

-- Tenancy 1
INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, status, paid_at)
SELECT t.tenancy_id, d.due_date, d.amount,
       CASE WHEN d.due_date <= CURRENT_DATE THEN 'paid' ELSE 'pending' END,
       CASE WHEN d.due_date <= CURRENT_DATE THEN d.due_date + interval '3 days' ELSE NULL END
FROM tenancy t
JOIN (VALUES
    (1, (SELECT session_start FROM p1_session),                       425000.00),
    (1, (SELECT (session_start + interval '6 months')::date FROM p1_session), 425000.00)
) AS d(ten_no, due_date, amount) ON d.ten_no = t.tenancy_id
WHERE t.tenancy_id = 1;

-- Tenancy 2
INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, status, paid_at)
SELECT t.tenancy_id, d.due_date, d.amount,
       CASE WHEN d.due_date <= CURRENT_DATE THEN 'paid' ELSE 'pending' END,
       CASE WHEN d.due_date <= CURRENT_DATE THEN d.due_date + interval '4 days' ELSE NULL END
FROM tenancy t
JOIN (VALUES
    (2, (SELECT session_start FROM p1_session),                       400000.00),
    (2, (SELECT (session_start + interval '6 months')::date FROM p1_session), 400000.00)
) AS d(ten_no, due_date, amount) ON d.ten_no = t.tenancy_id
WHERE t.tenancy_id = 2;

-- Tenancy 3
INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, status, paid_at)
SELECT t.tenancy_id, d.due_date, d.amount,
       CASE WHEN d.due_date <= CURRENT_DATE THEN 'paid' ELSE 'pending' END,
       CASE WHEN d.due_date <= CURRENT_DATE THEN d.due_date + interval '5 days' ELSE NULL END
FROM tenancy t
JOIN (VALUES
    (3, (SELECT session_start FROM p1_session),                       130000.00),
    (3, (SELECT (session_start + interval '4 months')::date FROM p1_session), 130000.00),
    (3, (SELECT (session_start + interval '8 months')::date FROM p1_session), 120000.00)
) AS d(ten_no, due_date, amount) ON d.ten_no = t.tenancy_id
WHERE t.tenancy_id = 3;

-- Tenancy 4
INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, status, paid_at)
SELECT t.tenancy_id, d.due_date, d.amount,
       CASE WHEN d.due_date <= CURRENT_DATE THEN 'paid' ELSE 'pending' END,
       CASE WHEN d.due_date <= CURRENT_DATE THEN d.due_date + interval '2 days' ELSE NULL END
FROM tenancy t
JOIN (VALUES
    (4, (SELECT session_start FROM p1_session), 245000.00)
) AS d(ten_no, due_date, amount) ON d.ten_no = t.tenancy_id
WHERE t.tenancy_id = 4;

-- Tenancy 5
INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, status, paid_at)
SELECT t.tenancy_id, d.due_date, d.amount,
       CASE WHEN d.due_date <= CURRENT_DATE THEN 'paid' ELSE 'pending' END,
       CASE WHEN d.due_date <= CURRENT_DATE THEN d.due_date + interval '6 days' ELSE NULL END
FROM tenancy t
JOIN (VALUES
    (5, (SELECT session_start FROM p1_session),                       150000.00),
    (5, (SELECT (session_start + interval '4 months')::date FROM p1_session), 150000.00),
    (5, (SELECT (session_start + interval '8 months')::date FROM p1_session), 150000.00)
) AS d(ten_no, due_date, amount) ON d.ten_no = t.tenancy_id
WHERE t.tenancy_id = 5;

-- Tenancy 6
INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, status, paid_at)
SELECT t.tenancy_id, d.due_date, d.amount,
       CASE WHEN d.due_date <= CURRENT_DATE THEN 'paid' ELSE 'pending' END,
       CASE WHEN d.due_date <= CURRENT_DATE THEN d.due_date + interval '7 days' ELSE NULL END
FROM tenancy t
JOIN (VALUES
    (6, (SELECT session_start FROM p1_session),                       120000.00),
    (6, (SELECT (session_start + interval '4 months')::date FROM p1_session), 100000.00),
    (6, (SELECT (session_start + interval '8 months')::date FROM p1_session), 100000.00)
) AS d(ten_no, due_date, amount) ON d.ten_no = t.tenancy_id
WHERE t.tenancy_id = 6;

-- Tenancy 7
INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, status, paid_at)
SELECT t.tenancy_id, d.due_date, d.amount,
       CASE WHEN d.due_date <= CURRENT_DATE THEN 'paid' ELSE 'pending' END,
       CASE WHEN d.due_date <= CURRENT_DATE THEN d.due_date + interval '8 days' ELSE NULL END
FROM tenancy t
JOIN (VALUES
    (7, (SELECT session_start FROM p1_session),                       360000.00),
    (7, (SELECT (session_start + interval '6 months')::date FROM p1_session), 360000.00)
) AS d(ten_no, due_date, amount) ON d.ten_no = t.tenancy_id
WHERE t.tenancy_id = 7;

-- Tenancy 8
INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, status, paid_at)
SELECT t.tenancy_id, d.due_date, d.amount,
       CASE WHEN d.due_date <= CURRENT_DATE THEN 'paid' ELSE 'pending' END,
       CASE WHEN d.due_date <= CURRENT_DATE THEN d.due_date + interval '9 days' ELSE NULL END
FROM tenancy t
JOIN (VALUES
    (8, (SELECT session_start FROM p1_session),                       157500.00),
    (8, (SELECT (session_start + interval '6 months')::date FROM p1_session), 157500.00)
) AS d(ten_no, due_date, amount) ON d.ten_no = t.tenancy_id
WHERE t.tenancy_id = 8;

-- 9. Waitlist entries (2) for the UNILAG single room type (room_type_id 1).
--    Pretend the two UNILAG single rooms are sold out, so two more UNILAG
--    students join the waitlist. Position is unique per room_type, and each
--    tenant can appear at most once per room_type.
INSERT INTO waitlist_entry (room_type_id, tenant_id, position) VALUES
    (1, 9, 1),
    (1, 10, 2);

-- 10. Maintenance tickets (4, one per category). ----------------------------
--     reported_at / resolved_at are anchored to now() so they never expire.
INSERT INTO maintenance_ticket (lodge_id, room_id, tenant_id, category, reported_at, resolved_at, status, summary) VALUES
    (1, 1,  1, 'plumbing',     now() - interval '10 days', now() - interval '7 days',  'resolved',    'Leaking tap in AH-S-101 bathroom'),
    (2, 9,  3, 'electrical',   now() - interval '4 days',  NULL,                       'in_progress', 'Power socket not working in YT-S2-201'),
    (3, 15, 5, 'furniture',    now() - interval '1 day',   NULL,                       'open',        'Broken study chair in OG-S2-201'),
    (4, 23, 7, 'pest_control', now() - interval '20 days', now() - interval '15 days', 'closed',      'Cockroach infestation in NS-S4-301 kitchenette');

COMMIT;

-- Done. The seed data is ready for the bulk generator.
