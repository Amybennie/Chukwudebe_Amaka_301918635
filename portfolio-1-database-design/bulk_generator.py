#!/usr/bin/env python3
# =============================================================================
# bulk_generator.py - bulk data generator for CampusNest (Portfolio 1)
# -----------------------------------------------------------------------------
# Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
# Course  : MIT 8103 Advanced Database Systems
# -----------------------------------------------------------------------------
# Adds a large, realistic dataset on top of seed.sql:
#
#   * 96 more lodges (24 near each school), each with single / shared_2 /
#     shared_4 room types priced for that area (Lagos dearer than Nsukka)
#   * ~15,000 lettable bed-spaces. A `room` row is ONE lettable bed-space:
#     a shared_4 room appears as four rows ...-B1 .. -B4 (see README).
#   * tenancies for four academic sessions (three past ones 'ended', the
#     current one 'active') plus early bookings for next session, with
#     occupancy that varies by lodge and session, ~3% cancelled bookings
#     and returning students who keep their tenant record
#   * 50,000+ tenancies, each tenant with exactly one guarantor
#   * rent instalments (1, 2 or 3 per tenancy) that sum EXACTLY to the
#     tenancy's annual rent; past ones paid, a few current ones overdue
#   * waitlists for the popular room types and ~2,500 maintenance tickets
#
# Every date is computed from today, so the data never goes stale.
# Constraint guarantees come from construction (sessions are half-open
# [start, end) ranges that never overlap; each tenant is placed at most once
# per session; instalments are split so they add up to the rent exactly).
#
# Connection: Unix socket, peer login as YOUR Linux user (setup.sh created a
# matching superuser role), so no password is needed.
#
# Run with:  python3 bulk_generator.py
# One transaction: if anything fails nothing is half-loaded, and the error
# is printed.
# =============================================================================
import random
import sys
import time
from datetime import date, datetime, timedelta
from decimal import Decimal, ROUND_DOWN

import psycopg2
from psycopg2.extras import execute_values

CONN = dict(host='/var/run/postgresql', dbname='campusnest')

random.seed(20260901)
TODAY = date.today()
# Nigerian academic sessions here run 1 Sept -> 1 Sept (half-open).
CUR_YEAR = TODAY.year if TODAY.month >= 9 else TODAY.year - 1
SESSIONS = [CUR_YEAR - 3, CUR_YEAR - 2, CUR_YEAR - 1, CUR_YEAR]  # start years
NEXT_SESSION = CUR_YEAR + 1                                     # early bookings

# ---------------------------------------------------------------------------
# Gender-matched Nigerian names, by ethnic group.
# ---------------------------------------------------------------------------
NAMES = {
    'yoruba': {
        'M': ['Adebayo', 'Babatunde', 'Olumide', 'Oluwaseun', 'Tunde', 'Kunle',
              'Gbenga', 'Femi', 'Ayodeji', 'Damilare', 'Segun', 'Tobiloba',
              'Ifeoluwa', 'Ademola', 'Olamide', 'Kehinde'],
        'F': ['Funke', 'Yetunde', 'Bolanle', 'Temitope', 'Folasade', 'Abimbola',
              'Adeola', 'Omolara', 'Titilayo', 'Morenike', 'Oluwakemi', 'Bisola',
              'Damilola', 'Ayomide', 'Oyinkansola', 'Mojisola'],
        'L': ['Adeyemi', 'Bakare', 'Adewale', 'Ogunleye', 'Ojo', 'Olatunji',
              'Odukoya', 'Adebayo', 'Ogundipe', 'Afolabi', 'Oyelaran',
              'Akinola', 'Adeleke', 'Ajayi', 'Oladipo', 'Ige'],
    },
    'igbo': {
        'M': ['Emeka', 'Ifeanyi', 'Obinna', 'Nnamdi', 'Tochukwu', 'Chukwuemeka',
              'Ikenna', 'Kelechi', 'Chinedu', 'Uchenna', 'Ebuka', 'Somtochukwu',
              'Chidera', 'Onyekachi'],
        'F': ['Ngozi', 'Chidinma', 'Amaka', 'Chinwe', 'Adaobi', 'Ifunanya',
              'Ogechi', 'Chiamaka', 'Nneka', 'Ebere', 'Chioma', 'Ujunwa',
              'Kosisochukwu', 'Adaeze'],
        'L': ['Eze', 'Obi', 'Nwosu', 'Okeke', 'Okafor', 'Madu', 'Okoro', 'Anya',
              'Onuoha', 'Ezeigbo', 'Chukwu', 'Nwankwo', 'Okonkwo', 'Udeh',
              'Ugwu', 'Agu', 'Chukwudebe', 'Nwachukwu'],
    },
    'hausa': {
        'M': ['Ibrahim', 'Musa', 'Lawal', 'Sani', 'Yusuf', 'Abdullahi', 'Bashir',
              'Nasir', 'Aminu', 'Usman', 'Kabiru', 'Haruna'],
        'F': ['Aisha', 'Fatima', 'Zainab', 'Halima', 'Hauwa', 'Khadija',
              'Maryam', 'Hadiza', 'Rukayya', 'Asmau', 'Safiya', 'Bilkisu'],
        'L': ['Bello', 'Danjuma', 'Mohammed', 'Abubakar', 'Gambo', 'Suleiman',
              'Yaro', 'Garba', 'Shehu', 'Umar', 'Aliyu', 'Idris'],
    },
}
# Ethnic mix differs by school (Nsukka is mostly Igbo, Lagos is mixed).
ETHNIC_MIX = {
    'UNILAG':   [('yoruba', 50), ('igbo', 32), ('hausa', 18)],
    'YABATECH': [('yoruba', 55), ('igbo', 33), ('hausa', 12)],
    'LASU':     [('yoruba', 62), ('igbo', 28), ('hausa', 10)],
    'UNN':      [('igbo', 80), ('yoruba', 10), ('hausa', 10)],
}

SCHOOL_AREA = {
    'UNILAG':   ('Lagos', [('Akoka', ['Iwaya Road', 'Community Road', 'St. Finbarrs College Road', 'Abule-Oja Street']),
                           ('Bariga', ['Ilaje Road', 'Oworo Road'])]),
    'YABATECH': ('Lagos', [('Yaba', ['Herbert Macaulay Way', 'Murtala Muhammed Way', 'Montgomery Road']),
                           ('Ebute Metta', ['Borno Way', 'Freeman Street'])]),
    'LASU':     ('Lagos', [('Ojo', ['Iba Road', 'Ojo-Igbede Road', 'LASU-Isheri Road']),
                           ('Iba', ['Iba Estate Road', 'Ikemba Street'])]),
    'UNN':      ('Enugu', [('Nsukka', ['Odenigbo Road', 'Odim Street', 'Hilltop Road']),
                           ('Odenigbo', ['Ezema Street', 'Aku Road'])]),
}
LODGE_WORDS = ['Haven', 'Court', 'Suites', 'Residence', 'Villa', 'Lodge',
               'Apartments', 'Hostel', 'Gardens', 'Annex']
LODGE_PREFIX = ['Royal', 'Mercy', 'Glory', 'Favour', 'Pinnacle', 'Cedar', 'Olive', 'Kings', 'Grace', 'Divine', 'Peace', 'Unity', 'Golden',
                'Emerald', 'Victory', 'Crystal', 'Zion', 'Diamond', 'Bethel',
                'Covenant', 'Silver', 'Sunrise', 'Heritage']
# Base annual rent (NGN) for a single room near each school.
BASE_SINGLE_RENT = {'UNILAG': 900000, 'YABATECH': 820000, 'LASU': 650000, 'UNN': 420000}
RELATIONSHIPS = ['Father', 'Mother', 'Uncle', 'Aunt', 'Elder brother',
                 'Elder sister', 'Guardian']
CATEGORIES = ['plumbing', 'electrical', 'furniture', 'pest_control', 'other']
FIX_DAYS = {'plumbing': (1, 6), 'electrical': (1, 5), 'furniture': (2, 12),
            'pest_control': (3, 15), 'other': (1, 10)}
SUMMARIES = {
    'plumbing': ['Leaking tap in bathroom', 'Blocked WC', 'No water from shower', 'Burst pipe under sink'],
    'electrical': ['Socket not working', 'Ceiling fan stopped', 'Prepaid meter shows error', 'Bulb holder sparking'],
    'furniture': ['Broken study chair', 'Wardrobe door off hinge', 'Bed slat cracked', 'Reading table wobbles'],
    'pest_control': ['Cockroaches in kitchenette', 'Bed bugs reported', 'Rats seen near store', 'Mosquito net torn'],
    'other': ['Window louvre broken', 'Door lock jammed', 'Roof leaking in rain', 'Paint peeling in room'],
}


def pick_weighted(pairs):
    total = sum(w for _, w in pairs)
    r = random.uniform(0, total)
    for item, w in pairs:
        r -= w
        if r <= 0:
            return item
    return pairs[-1][0]


def person(school):
    ethnic = pick_weighted(ETHNIC_MIX[school])
    sex = random.choice('MF')
    pool = NAMES[ethnic]
    return random.choice(pool[sex]), random.choice(pool['L']), ethnic


def phone():
    return f"+234 {random.choice(['803','806','813','816','703','706','805','807','815','905','802','808','812','701','902'])} " \
           f"{random.randint(100,999)} {random.randint(1000,9999)}"


def split_amount(total, n):
    """Split total into n parts that add up EXACTLY to total."""
    total = Decimal(str(total))
    base = (total / n).quantize(Decimal('0.01'), rounding=ROUND_DOWN)
    return [base] * (n - 1) + [total - base * (n - 1)]


def add_months(d, m):
    y, mo = divmod(d.month - 1 + m, 12)
    return date(d.year + y, mo + 1, 1)


def insert_returning(cur, sql, rows, page_size=2000):
    """execute_values with RETURNING, so we use the REAL generated ids."""
    out = []
    for s in range(0, len(rows), page_size):
        out += [r[0] for r in execute_values(cur, sql, rows[s:s + page_size],
                                             page_size=page_size, fetch=True)]
    return out


def main():
    t_start = time.time()
    conn = psycopg2.connect(**CONN)
    conn.autocommit = False
    cur = conn.cursor()
    cur.execute("SELECT count(*) FROM tenancy")
    if cur.fetchone()[0] > 1000:
        sys.exit("Bulk data already loaded - run schema.sql + seed.sql first (run_p1.sh does this).")

    # ------------------------------------------------------------------ lodges
    print("[1/7] Lodges and room types ...")
    lodge_rows = []
    used = set()
    for school, (state, areas) in SCHOOL_AREA.items():
        for _ in range(24):
            while True:
                nm = f"{random.choice(LODGE_PREFIX)} {random.choice(LODGE_WORDS)}"
                if nm not in used:
                    used.add(nm)
                    break
            town, streets = random.choice(areas)
            lodge_rows.append((nm, school, f"{random.randint(2, 48)} {random.choice(streets)}", town, state))
    new_lodges = insert_returning(cur,
        "INSERT INTO lodge (name, nearest_school, address_line, city, state) VALUES %s RETURNING lodge_id",
        lodge_rows)
    rt_rows = []
    for lid, row in zip(new_lodges, lodge_rows):
        school = row[1]
        f = random.uniform(0.8, 1.25)                 # cheaper or dearer lodge
        single = round(BASE_SINGLE_RENT[school] * f, -4)
        rt_rows += [(lid, 'single', single, 1),
                    (lid, 'shared_2', round(single * 0.55, -4), 2),
                    (lid, 'shared_4', round(single * 0.38, -4), 4)]
    execute_values(cur, "INSERT INTO room_type (lodge_id, name, annual_rent_ngn, capacity) VALUES %s", rt_rows)

    cur.execute("""SELECT l.lodge_id, l.nearest_school, l.name, rt.room_type_id, rt.name, rt.capacity, rt.annual_rent_ngn
                     FROM lodge l JOIN room_type rt USING (lodge_id) ORDER BY l.lodge_id, rt.room_type_id""")
    lodges = {}
    for lid, school, lname, rtid, rtname, cap, rent in cur.fetchall():
        lodges.setdefault(lid, {'school': school, 'name': lname, 'types': []})
        lodges[lid]['types'].append((rtid, rtname, cap, rent))

    # --------------------------------------------------------- bed-spaces
    print("[2/7] Bed-spaces (one room row per lettable bed) ...")
    room_rows, room_meta = [], []
    for lid, info in lodges.items():
        prefix = ''.join(w[0] for w in info['name'].split()[:2]).upper() + str(lid)
        floors = random.randint(2, 4)
        for rtid, rtname, cap, rent in info['types']:
            n_physical = {'single': random.randint(25, 45),
                          'shared_2': random.randint(20, 35),
                          'shared_4': random.randint(10, 20)}[rtname]
            for p in range(n_physical):
                fl = random.randint(1, floors)
                num = f"{fl}{p:02d}{rtname[0].upper()}{cap}"
                for b in range(1, cap + 1):
                    code = f"{prefix}-{num}" if cap == 1 else f"{prefix}-{num}-B{b}"
                    room_rows.append((lid, rtid, code, fl))
                    room_meta.append((lid, rtid, rent, info['school']))
    room_ids = insert_returning(cur,
        "INSERT INTO room (lodge_id, room_type_id, room_code, floor) VALUES %s RETURNING room_id", room_rows)
    print(f"      {len(room_ids):,} bed-spaces in {len(lodges)} lodges")

    # ----------------------------------------------- tenants + tenancies
    print("[3/7] Tenants, guarantors and tenancies per session ...")
    tenants = []          # (first, last, ethnic, school, admit_year)
    tenancy_plan = []     # (room_idx, tenant_idx, start, end, rent, status)
    lodge_occ = {lid: random.uniform(0.76, 0.98) for lid in lodges}
    prev_session = {}     # room_idx -> tenant_idx in previous session

    def new_tenant(school, admit_year):
        first, last, eth = person(school)
        tenants.append((first, last, eth, school, admit_year))
        return len(tenants) - 1

    for yr in SESSIONS + [NEXT_SESSION]:
        start, end = date(yr, 9, 1), date(yr + 1, 9, 1)
        this_session = {}
        is_next = yr == NEXT_SESSION
        for ri, (lid, rtid, rent, school) in enumerate(room_meta):
            occ = lodge_occ[lid] * random.uniform(0.93, 1.03)
            if is_next:
                occ = 0.12            # only early bookings for next session so far
            if random.random() > occ:
                continue
            # returning student keeps the same bed-space 55% of the time
            if ri in prev_session and random.random() < 0.55:
                ti = prev_session[ri]
            else:
                ti = new_tenant(school, yr)
            if random.random() < 0.03 and not is_next:
                # booking cancelled after a failed payment; a new student took the bed
                tenancy_plan.append((ri, new_tenant(school, yr), start, end, rent, 'cancelled'))
            status = 'ended' if end <= TODAY else 'active'
            tenancy_plan.append((ri, ti, start, end, rent, status))
            this_session[ri] = ti
        prev_session = this_session
        print(f"      session {yr}/{(yr + 1) % 100:02d}: {len(this_session):,} beds let")

    # waitlist applicants (prospective students with no bed yet)
    wait_rows_plan = []
    popular = [(t[0], lid) for lid, info in lodges.items()
               if lid in new_lodges and lodge_occ[lid] > 0.93 for t in info['types']]
    for rtid, lid in popular:
        for pos in range(1, random.randint(3, 14)):
            wait_rows_plan.append((rtid, new_tenant(lodges[lid]['school'], NEXT_SESSION), pos))

    t_rows, seen_email = [], set()
    for i, (first, last, eth, school, adm) in enumerate(tenants):
        email = f"{first}.{last}{i + 1}@mail.example.ng".lower()
        matric = f"{school}/{adm % 100:02d}/{random.randint(10000, 99999)}"
        t_rows.append((f"{first} {last}", email, phone(), matric, school))
    tenant_ids = insert_returning(cur,
        "INSERT INTO tenant (full_name, email, phone, student_matric, nearest_school) VALUES %s RETURNING tenant_id",
        t_rows, 5000)
    g_rows = []
    for tid, (first, last, eth, school, adm) in zip(tenant_ids, tenants):
        rel = random.choice(RELATIONSHIPS)
        gsex = 'F' if rel in ('Mother', 'Aunt', 'Elder sister') else 'M'
        gfirst = random.choice(NAMES[eth][gsex])
        glast = last if rel in ('Father', 'Mother', 'Elder brother', 'Elder sister') else random.choice(NAMES[eth]['L'])
        state, areas = SCHOOL_AREA[school]
        town = random.choice(areas)[0]
        g_rows.append((tid, f"{gfirst} {glast}", phone(), None, rel,
                       f"{random.randint(1, 60)} {random.choice(['Church', 'Market', 'Station', 'Old Airport', 'Ziks'])} Road, {town}, {state} State"))
    execute_values(cur, "INSERT INTO guarantor (tenant_id, full_name, phone, email, relationship, home_address) VALUES %s",
                   g_rows, page_size=5000)
    print(f"      {len(tenant_ids):,} tenants + {len(g_rows):,} guarantors")

    ten_rows = [(room_ids[ri], tenant_ids[ti], s, e, rent, st) for ri, ti, s, e, rent, st in tenancy_plan]
    tenancy_ids = insert_returning(cur,
        "INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn, status) VALUES %s RETURNING tenancy_id",
        ten_rows, 5000)
    print(f"      {len(tenancy_ids):,} tenancies "
          f"({sum(1 for r in ten_rows if r[5] == 'cancelled'):,} cancelled)")

    # -------------------------------------------------------- instalments
    print("[4/7] Rent instalments (sum exactly to annual rent) ...")
    inst = []
    for ten_id, (rid, tid, s, e, rent, st) in zip(tenancy_ids, ten_rows):
        if st == 'cancelled':
            continue                      # payment failed -> no instalments kept
        n = random.choice([1, 2, 2, 3, 3, 3])
        for j, amt in enumerate(split_amount(rent, n)):
            due = add_months(s, j * (12 // n))
            if due <= TODAY:
                late = random.random() < 0.06 and e > TODAY   # current session arrears
                if late:
                    inst.append((ten_id, due, amt, 'overdue', None))
                else:
                    paid = datetime.combine(due, datetime.min.time()) + timedelta(
                        days=random.randint(-14, 9), hours=random.randint(8, 20))
                    paid = min(paid, datetime.now() - timedelta(hours=1))
                    inst.append((ten_id, due, amt, 'paid', paid))
            else:
                inst.append((ten_id, due, amt, 'pending', None))
    execute_values(cur, "INSERT INTO rent_instalment (tenancy_id, due_date, amount_ngn, status, paid_at) VALUES %s",
                   inst, page_size=5000)
    print(f"      {len(inst):,} instalments")

    # ------------------------------------------------------------ waitlist
    print("[5/7] Waitlist ...")
    execute_values(cur, "INSERT INTO waitlist_entry (room_type_id, tenant_id, position, joined_at) VALUES %s",
                   [(rt, tenant_ids[ti], pos, datetime.now() - timedelta(days=30 - pos, hours=random.randint(0, 20)))
                    for rt, ti, pos in wait_rows_plan])
    print(f"      {len(wait_rows_plan):,} waitlist entries on {len(popular)} popular room types")

    # --------------------------------------------------------- maintenance
    print("[6/7] Maintenance tickets ...")
    active = [(room_ids[ri], tenant_ids[ti], room_meta[ri][0], s)
              for ri, ti, s, e, rent, st in tenancy_plan if st != 'cancelled' and s <= TODAY]
    m_rows = []
    for _ in range(2500):
        rid, tid, lid, s = random.choice(active)
        cat = pick_weighted([('plumbing', 30), ('electrical', 25), ('furniture', 18), ('pest_control', 12), ('other', 15)])
        span = (min(TODAY, add_months(s, 12)) - s).days
        reported = datetime.combine(s, datetime.min.time()) + timedelta(days=random.randint(0, max(span - 1, 0)),
                                                                        hours=random.randint(7, 21))
        age = (datetime.now() - reported).days
        lo, hi = FIX_DAYS[cat]
        fix = random.randint(lo, hi)
        if age > fix + 2:
            status = random.choice(['resolved', 'closed', 'closed'])
            resolved = reported + timedelta(days=fix, hours=random.randint(0, 10))
        else:
            status, resolved = random.choice(['open', 'in_progress']), None
        m_rows.append((lid, rid, tid, cat, reported, resolved, status, random.choice(SUMMARIES[cat])))
    execute_values(cur, "INSERT INTO maintenance_ticket (lodge_id, room_id, tenant_id, category, reported_at, resolved_at, status, summary) VALUES %s",
                   m_rows, page_size=2500)
    print(f"      {len(m_rows):,} tickets")

    # -------------------------------------------------------------- commit
    print("[7/7] COMMIT (the deferred guarantor trigger checks every new tenant now) ...")
    t0 = time.time()
    try:
        conn.commit()
    except Exception as exc:
        conn.rollback()
        print(f"COMMIT FAILED - nothing was loaded: {exc}")
        raise
    print(f"      commit took {time.time() - t0:.1f}s")

    cur = conn.cursor()
    tables = ['lodge', 'room_type', 'room', 'tenant', 'guarantor', 'tenancy',
              'rent_instalment', 'waitlist_entry', 'maintenance_ticket']
    counts = {}
    for t in tables:
        cur.execute(f"SELECT count(*) FROM {t}")
        counts[t] = cur.fetchone()[0]
    cur.execute("""SELECT count(*) FROM (SELECT t.tenancy_id FROM tenancy t JOIN rent_instalment i USING (tenancy_id)
                    GROUP BY t.tenancy_id, t.annual_rent_ngn HAVING sum(i.amount_ngn) <> t.annual_rent_ngn) x""")
    mismatched = cur.fetchone()[0]
    print()
    print("=" * 60)
    print(" BULK GENERATOR COMPLETE")
    print("=" * 60)
    for t in tables:
        print(f"  {t:22s}: {counts[t]:>10,}")
    print(f"  tenancies whose instalments != rent : {mismatched}")
    print(f"  elapsed                             : {time.time() - t_start:.1f}s")
    print("=" * 60)
    assert counts['tenancy'] >= 50000, f"tenancies below 50,000: {counts['tenancy']}"
    assert mismatched == 0
    print("Target met: 50,000+ tenancies; every tenancy's instalments add up to its rent.")
    conn.close()


if __name__ == '__main__':
    main()
