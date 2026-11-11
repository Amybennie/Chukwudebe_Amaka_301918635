#!/usr/bin/env python3
# =============================================================================
# run_race_demos.py - Portfolio 3 concurrency demos with TWO real sessions
# Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
# Case    : CampusNest - Private Student Accommodation Booking
# -----------------------------------------------------------------------------
# Opens two separate PostgreSQL connections ("Session A" and "Session B",
# exactly like two psql terminals) and runs six scenarios step by step.
# Where one session has to wait for the other, the waiting statement runs
# in a thread so you can see it block and then finish.
#
#   Part 1  The bug: check-then-insert with no protection -> double booking
#   Part 2  Fix 1 (main fix): the EXCLUSION CONSTRAINT refuses the overlap
#   Part 3  Fix 2: reserve_room() with FOR UPDATE SKIP LOCKED -> two beds, no wait
#   Part 4  SERIALIZABLE isolation catches the same race with error 40001
#   Part 5  READ COMMITTED vs REPEATABLE READ (non-repeatable read)
#   Part 6  Deadlock, and the fix: lock rows in one fixed order
#
# Every row the demos create is deleted at the end, so it can be re-run.
# Output is real; run_p3.sh saves it to race_demos_output.log.
# =============================================================================
import threading
import time
from datetime import datetime

import psycopg2
from psycopg2 import errors

DSN = dict(host='/var/run/postgresql', dbname='campusnest')
T0 = time.time()


def ts():
    return f"[{time.time() - T0:6.2f}s]"


def say(who, text):
    print(f"{ts()} {who:<9} {text}", flush=True)


def header(title):
    print("\n" + "=" * 72)
    print(" " + title)
    print("=" * 72, flush=True)


def connect(name, autocommit=False):
    c = psycopg2.connect(**DSN, application_name=f"p3_{name}")
    c.autocommit = autocommit
    return c


def one(conn, sql, args=None):
    with conn.cursor() as cur:
        cur.execute(sql, args)
        return cur.fetchone() if cur.description else None


def run_in_thread(fn):
    box = {}

    def target():
        try:
            box['result'] = fn()
        except Exception as exc:          # keep the real error to print it
            box['error'] = exc
    th = threading.Thread(target=target)
    th.start()
    return th, box


admin = connect('admin', autocommit=True)
created_tenancies = []

# ---------------------------------------------------------------------------
# Pick real data: a room type with free beds next session, and free tenants
# ---------------------------------------------------------------------------
sess = one(admin, "SELECT next_session_start(), (next_session_start() + interval '12 months')::date")
S, E = sess
rt_id, lodge, free_beds = one(admin, """
    SELECT rt.room_type_id, l.name || ' (' || rt.name || ')', count(*)
      FROM room r JOIN room_type rt USING (room_type_id) JOIN lodge l ON l.lodge_id = r.lodge_id
     WHERE NOT EXISTS (SELECT 1 FROM tenancy t WHERE t.room_id = r.room_id AND t.status <> 'cancelled'
                         AND daterange(t.start_date, t.end_date) && daterange(%s, %s))
     GROUP BY rt.room_type_id, l.name, rt.name
    HAVING count(*) >= 3
     ORDER BY rt.room_type_id LIMIT 1""", (S, E))
bed_id, bed_code = one(admin, """
    SELECT r.room_id, r.room_code FROM room r
     WHERE r.room_type_id = %s
       AND NOT EXISTS (SELECT 1 FROM tenancy t WHERE t.room_id = r.room_id AND t.status <> 'cancelled'
                         AND daterange(t.start_date, t.end_date) && daterange(%s, %s))
     ORDER BY r.room_id LIMIT 1""", (rt_id, S, E))
with admin.cursor() as cur:
    cur.execute("""
        SELECT tn.tenant_id, tn.full_name FROM tenant tn
         WHERE NOT EXISTS (SELECT 1 FROM tenancy t WHERE t.tenant_id = tn.tenant_id
                             AND t.status <> 'cancelled' AND t.end_date > %s)
           AND NOT EXISTS (SELECT 1 FROM waitlist_entry w WHERE w.tenant_id = tn.tenant_id)
         ORDER BY tn.tenant_id LIMIT 4""", (S,))
    students = cur.fetchall()
(ada_id, ada), (bayo_id, bayo), (t3_id, t3), (t4_id, t4) = students

print(f"Run at {datetime.now():%Y-%m-%d %H:%M:%S}")
print(f"Next session      : {S} to {E}")
print(f"Room type         : {rt_id} = {lodge}, {free_beds} free beds next session")
print(f"Contested bed     : {bed_code} (room_id {bed_id})")
print(f"Student in A      : {ada} (tenant {ada_id})")
print(f"Student in B      : {bayo} (tenant {bayo_id})")

# ===========================================================================
header("PART 1 - THE BUG: check-then-insert with no protection")
# ===========================================================================
print("A copy of the booking table WITHOUT the exclusion constraint shows what\n"
      "happens if the application only checks 'is the bed free?' and then inserts.")
admin.cursor().execute("DROP TABLE IF EXISTS p3_naive_booking; "
                       "CREATE TABLE p3_naive_booking (room_id BIGINT, tenant_id BIGINT, start_date DATE, end_date DATE)")
A, B = connect('A'), connect('B')
check = "SELECT count(*) FROM p3_naive_booking WHERE room_id = %s AND daterange(start_date,end_date) && daterange(%s,%s)"
ins = "INSERT INTO p3_naive_booking VALUES (%s, %s, %s, %s)"
say('Session A', f"BEGIN; is {bed_code} free?  bookings found = {one(A, check, (bed_id, S, E))[0]}")
say('Session B', f"BEGIN; is {bed_code} free?  bookings found = {one(B, check, (bed_id, S, E))[0]}")
one(A, ins, (bed_id, ada_id, S, E)); say('Session A', f"INSERT booking for {ada}")
one(B, ins, (bed_id, bayo_id, S, E)); say('Session B', f"INSERT booking for {bayo}")
A.commit(); say('Session A', "COMMIT")
B.commit(); say('Session B', "COMMIT")
with admin.cursor() as cur:
    cur.execute("SELECT b.room_id, t.full_name, b.start_date, b.end_date FROM p3_naive_booking b "
                "JOIN tenant t USING (tenant_id) ORDER BY t.full_name")
    rows = cur.fetchall()
print(f"\nResult: {len(rows)} bookings for ONE bed in the same session -> DOUBLE BOOKING")
for r in rows:
    print(f"   room_id {r[0]}  {r[1]:<25} {r[2]} -> {r[3]}")

# ===========================================================================
header("PART 2 - FIX 1 (main fix): the exclusion constraint tenancy_no_room_overlap")
# ===========================================================================
print("Same race on the real tenancy table. The constraint makes B wait for A,\n"
      "then refuses B's overlapping tenancy.")
A, B = connect('A'), connect('B')
ins_t = ("INSERT INTO tenancy (room_id, tenant_id, start_date, end_date, annual_rent_ngn, status) "
         "SELECT %s, %s, %s, %s, annual_rent_ngn, 'active' FROM room_type WHERE room_type_id = %s RETURNING tenancy_id")
say('Session A', f"BEGIN; is {bed_code} free?  found = {one(A, 'SELECT count(*) FROM tenancy WHERE room_id=%s AND status<>%s AND daterange(start_date,end_date) && daterange(%s,%s)', (bed_id, 'cancelled', S, E))[0]}")
say('Session B', f"BEGIN; is {bed_code} free?  found = {one(B, 'SELECT count(*) FROM tenancy WHERE room_id=%s AND status<>%s AND daterange(start_date,end_date) && daterange(%s,%s)', (bed_id, 'cancelled', S, E))[0]}")
tid_a = one(A, ins_t, (bed_id, ada_id, S, E, rt_id))[0]
say('Session A', f"INSERT tenancy {tid_a} for {ada} (not committed yet)")
th, box = run_in_thread(lambda: one(B, ins_t, (bed_id, bayo_id, S, E, rt_id)))
time.sleep(1.5)
say('Session B', f"INSERT for {bayo} ... still waiting after 1.5 s (blocked by A)" if th.is_alive()
    else "INSERT finished early (unexpected)")
A.commit(); say('Session A', "COMMIT")
created_tenancies.append(tid_a)
th.join()
if 'error' in box:
    e = box['error']
    say('Session B', f"ERROR {e.pgcode}: {e.pgerror.splitlines()[0]}")
    B.rollback(); say('Session B', "ROLLBACK - the bed stays with " + ada)
else:
    say('Session B', f"INSERT succeeded: {box['result']}  <-- constraint NOT working")
    B.rollback()
n = one(admin, "SELECT count(*) FROM tenancy WHERE room_id=%s AND status<>'cancelled' AND daterange(start_date,end_date) && daterange(%s,%s)", (bed_id, S, E))[0]
print(f"\nResult: {n} tenancy on {bed_code} for the session -> no double booking")

# ===========================================================================
header("PART 3 - FIX 2: reserve_room() picks beds with FOR UPDATE SKIP LOCKED")
# ===========================================================================
print("Two students ask for the same room type at the same moment.\n"
      "B skips the bed A has locked and gets the next free bed, without waiting.")
A, B = connect('A'), connect('B')
ra = one(A, "SELECT outcome, tenancy_id, room_code FROM reserve_room(%s, %s)", (t3_id, rt_id))
say('Session A', f"BEGIN; reserve_room({t3}) -> {ra[0]}, bed {ra[2]} (locked, not committed)")
t_start = time.time()
rb = one(B, "SELECT outcome, tenancy_id, room_code FROM reserve_room(%s, %s)", (t4_id, rt_id))
say('Session B', f"BEGIN; reserve_room({t4}) -> {rb[0]}, bed {rb[2]} after {(time.time() - t_start) * 1000:.0f} ms (no wait)")
A.commit(); say('Session A', "COMMIT")
B.commit(); say('Session B', "COMMIT")
created_tenancies += [x for x in (ra[1], rb[1]) if x]
print(f"\nResult: both students booked, different beds ({ra[2]} and {rb[2]})")

# ===========================================================================
header("PART 4 - SERIALIZABLE isolation catches the race (no constraint needed)")
# ===========================================================================
print("Part 1 again on the unprotected table, but both sessions use SERIALIZABLE.")
admin.cursor().execute("TRUNCATE p3_naive_booking")
A, B = connect('A'), connect('B')
for c in (A, B):
    c.set_session(isolation_level='SERIALIZABLE')
say('Session A', f"BEGIN ISOLATION LEVEL SERIALIZABLE; free? found = {one(A, check, (bed_id, S, E))[0]}")
say('Session B', f"BEGIN ISOLATION LEVEL SERIALIZABLE; free? found = {one(B, check, (bed_id, S, E))[0]}")
one(A, ins, (bed_id, ada_id, S, E)); say('Session A', f"INSERT booking for {ada}")
one(B, ins, (bed_id, bayo_id, S, E)); say('Session B', f"INSERT booking for {bayo}")
A.commit(); say('Session A', "COMMIT ok")
try:
    B.commit(); say('Session B', "COMMIT ok  <-- race NOT caught")
except errors.SerializationFailure as e:
    say('Session B', f"COMMIT -> ERROR {e.pgcode}: {e.pgerror.splitlines()[0]}")
    B.rollback()
    say('Session B', f"retry: free? found = {one(B, check, (bed_id, S, E))[0]} -> bed taken, show B another bed")
    B.rollback()
print(f"\nResult: {one(admin, 'SELECT count(*) FROM p3_naive_booking')[0]} booking kept; the second one was refused with 40001")

# ===========================================================================
header("PART 5 - READ COMMITTED vs REPEATABLE READ")
# ===========================================================================
lodge_id = one(admin, "SELECT lodge_id FROM room WHERE room_id = %s", (bed_id,))[0]
count_q = ("SELECT count(*) FROM tenancy t JOIN room r USING (room_id) "
           "WHERE r.lodge_id = %s AND t.start_date = %s AND t.status <> 'cancelled'")
spare = one(admin, """SELECT r.room_id FROM room r WHERE r.lodge_id = %s AND NOT EXISTS
             (SELECT 1 FROM tenancy t WHERE t.room_id = r.room_id AND t.status <> 'cancelled'
              AND daterange(t.start_date,t.end_date) && daterange(%s,%s)) ORDER BY room_id DESC LIMIT 1""",
            (lodge_id, S, E))[0]
spare_tenant = one(admin, """SELECT tn.tenant_id FROM tenant tn WHERE NOT EXISTS (SELECT 1 FROM tenancy t
             WHERE t.tenant_id = tn.tenant_id AND t.status <> 'cancelled' AND t.end_date > %s)
             AND tn.tenant_id NOT IN (%s,%s,%s,%s)
             AND NOT EXISTS (SELECT 1 FROM waitlist_entry w WHERE w.tenant_id = tn.tenant_id)
             ORDER BY tenant_id OFFSET 10 LIMIT 1""", (S, ada_id, bayo_id, t3_id, t4_id))[0]
for level in ('READ COMMITTED', 'REPEATABLE READ'):
    print(f"\n--- Session A at {level} ---")
    A, B = connect('A'), connect('B', autocommit=True)
    A.set_session(isolation_level=level)
    say('Session A', f"BEGIN; next-session bookings in this lodge = {one(A, count_q, (lodge_id, S))[0]}")
    tid = one(B, ins_t, (spare, spare_tenant, S, E, one(admin, 'SELECT room_type_id FROM room WHERE room_id=%s', (spare,))[0]))[0]
    say('Session B', f"INSERT tenancy {tid} in the same lodge; COMMIT")
    say('Session A', f"same query again, same transaction  = {one(A, count_q, (lodge_id, S))[0]}")
    A.commit()
    one(admin, "DELETE FROM tenancy WHERE tenancy_id = %s", (tid,))
print("\nResult: READ COMMITTED saw B's new row mid-transaction (non-repeatable read);\n"
      "REPEATABLE READ kept the snapshot from its first query.")

# ===========================================================================
header("PART 6 - DEADLOCK, and the fix (lock rows in one fixed order)")
# ===========================================================================
r1, r2 = (x[0] for x in [one(admin, "SELECT min(instalment_id) FROM rent_instalment WHERE status='pending'"),
                         one(admin, "SELECT min(instalment_id) FROM rent_instalment WHERE status='pending' AND instalment_id > (SELECT min(instalment_id) FROM rent_instalment WHERE status='pending')")])
print(f"Two pending instalments: {r1} and {r2}. A finance clerk (A) and the payment\n"
      "webhook (B) each update both, in OPPOSITE order. Everything is rolled back.")
upd = "UPDATE rent_instalment SET due_date = due_date WHERE instalment_id = %s"
A, B = connect('A'), connect('B')
one(A, upd, (r1,)); say('Session A', f"BEGIN; UPDATE instalment {r1}  (A locks {r1})")
one(B, upd, (r2,)); say('Session B', f"BEGIN; UPDATE instalment {r2}  (B locks {r2})")
tha, boxa = run_in_thread(lambda: one(A, upd, (r2,)))
time.sleep(0.5); say('Session A', f"UPDATE instalment {r2} ... waiting for B")
thb, boxb = run_in_thread(lambda: one(B, upd, (r1,)))
say('Session B', f"UPDATE instalment {r1} ... waiting for A  -> each waits for the other")
tha.join(); thb.join()
for who, box, conn in (('Session A', boxa, A), ('Session B', boxb, B)):
    if 'error' in box:
        say(who, f"ERROR {box['error'].pgcode}: {box['error'].pgerror.splitlines()[0]}")
    else:
        say(who, "UPDATE finished (the other session was chosen as the deadlock victim)")
    conn.rollback()
say('both', "ROLLBACK")

print("\n--- Fix: both sessions lock the two rows in ascending id order first ---")
lock_both = "SELECT instalment_id FROM rent_instalment WHERE instalment_id IN (%s,%s) ORDER BY instalment_id FOR UPDATE"
A, B = connect('A'), connect('B')
one(A, lock_both, (r1, r2)); say('Session A', f"BEGIN; lock {r1},{r2} in id order -> got both")
thb, boxb = run_in_thread(lambda: (one(B, lock_both, (r1, r2)), one(B, upd, (r2,)), one(B, upd, (r1,))))
time.sleep(0.5); say('Session B', "lock in id order ... waits politely (no cycle possible)")
one(A, upd, (r2,)); one(A, upd, (r1,)); say('Session A', f"UPDATE {r2} and {r1}; ROLLBACK (demo only, releases the locks)")
A.rollback()
thb.join()
say('Session B', "got the locks, UPDATE both -> " + ("ERROR " + boxb['error'].pgcode if 'error' in boxb else "done, no deadlock"))
B.rollback()

# ---------------------------------------------------------------------------
header("CLEAN-UP")
for tid in created_tenancies:
    one(admin, "DELETE FROM tenancy WHERE tenancy_id = %s", (tid,))
admin.cursor().execute("DROP TABLE IF EXISTS p3_naive_booking")
print(f"Removed {len(created_tenancies)} demo tenancies (and their instalments) and the naive table.")
print("All six parts finished.")
