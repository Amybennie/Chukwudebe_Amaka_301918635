> **Automatic version:** `run_race_demos.py` (run by `run_p3.sh`) performs all of these parts with two real sessions and saves the real output to `race_demos_output.log`. This guide is for repeating a part by hand.

# Race Condition Demo - Two-Terminal Guide

**Portfolio 3 - Transactions and Concurrency**
**Student:** Amaka Benedicta Chukwudebe | **Matric:** 2026/A/MIT/0517
**Course:** MIT 8103 Advanced Database Systems | **Case:** CampusNest

---

## What this guide demonstrates

This is the **centerpiece** of Portfolio 3. It shows, in three acts, the most
important concurrency problem in a booking system: **two students race to grab
the last free room of a type, and both think they got it**.

You will run the demo by opening **two separate Codespaces terminals** and
typing the SQL exactly as written. Each part has:

1. **Setup SQL** you run once in a single terminal to pick the values you will
   use.
2. **Numbered steps** for Terminal 1 and Terminal 2.
3. **What to expect** for each step.
4. **`[paste real output here]`** placeholders where you will paste the actual
   `psql` output you observed, for the LMS submission.

> **Honesty rule:** do NOT fabricate output. If a step did not produce the
> expected result, write what actually happened and explain it. The lecturer
> can verify by re-running.

---

## Open two terminals

In Codespaces, open **two separate terminals** (Terminal > New Terminal, or
`Ctrl+Alt+T`). In **both** terminals, connect to the `campusnest` database
through the Unix socket as the `postgres` OS user:

```bash
# Run this in BOTH Terminal 1 and Terminal 2:
sudo runuser -u postgres -- psql -d campusnest
```

You should see the `campusnest=#` prompt in both terminals.

> Codespaces rule: `sudo runuser -u postgres -- psql ...` is the only correct
> way. Never `sudo -u postgres` - it fails in Codespaces.

---

## Compute the session window (run once, in Terminal 1)

Every demo uses the same session window: **the first day of next month through
the same day twelve months later** (a full academic session). Run this once in
Terminal 1 to see the values you will substitute into the SQL below:

```sql
SELECT (date_trunc('month', now()) + interval '1 month')::date  AS session_start,
       (date_trunc('month', now()) + interval '13 months')::date AS session_end;
```

**Expected output** (a single row, two columns, your dates will differ):

```
 session_start | session_end
---------------+-------------
 YYYY-MM-DD     | YYYY-MM-DD+12months
```

Write down the two dates returned. You will substitute them wherever this
guide writes `<session_start>` and `<session_end>`.

[paste real output here]

---

## Find candidate room types and tenants (run once, in Terminal 1)

Run this in Terminal 1 to find which room types have free rooms for the
session window, and to pick two tenants who do not already have an active
tenancy:

```sql
-- Free-room count per room_type, for the next session window.
WITH session_window AS (
    SELECT (date_trunc('month', now()) + interval '1 month')::date  AS sstart,
           (date_trunc('month', now()) + interval '13 months')::date AS send
)
SELECT rt.room_type_id,
       l.name         AS lodge_name,
       rt.name        AS room_type,
       rt.annual_rent_ngn,
       count(r.room_id) FILTER (
           WHERE NOT EXISTS (
               SELECT 1 FROM tenancy t
                WHERE t.room_id = r.room_id
                  AND t.status <> 'cancelled'
                  AND daterange(t.start_date, t.end_date)
                      && daterange(sw.sstart, sw.send)
           )
       ) AS free_rooms_for_next_session
  FROM room_type rt
  JOIN lodge l   ON l.lodge_id   = rt.lodge_id
  JOIN room r    ON r.room_type_id = rt.room_type_id
 CROSS JOIN session_window sw
 GROUP BY rt.room_type_id, l.name, rt.name, rt.annual_rent_ngn
 ORDER BY free_rooms_for_next_session DESC, rt.room_type_id;
```

[paste real output here]

Pick the values you will use and substitute them into the SQL below:

| Placeholder             | Where you find it                                            |
|-------------------------|--------------------------------------------------------------|
| `<room_type_id>`        | A `room_type_id` from the query above that has `>= 1` free room. For Part A and Part B, **any** room type with at least one free room will do (both terminals will see the same lowest-`room_id` room because of `ORDER BY r.room_id LIMIT 1`). For Part C, pick a room type with **at least 2** free rooms. |
| `<session_start>`       | The `session_start` date printed by the previous query.      |
| `<session_end>`         | The `session_end` date printed by the previous query.        |

Then pick two tenants:

```sql
SELECT tenant_id, full_name, nearest_school
  FROM tenant
 ORDER BY tenant_id
 LIMIT 5;
```

[paste real output here]

Pick two different `tenant_id` values and substitute them as `<tenant1_id>`
and `<tenant2_id>` below. They should not already have a tenancy that overlaps
the session window (you can verify with `SELECT * FROM tenancy WHERE tenant_id =
<X> AND daterange(start_date,end_date) && daterange('<session_start>','<session_end>')`).

---

## RESET between demos (run in BOTH terminals before each Part)

Before starting each Part, make sure neither terminal has an open transaction
and that the previous Part's test data is gone. Run these in **both**
terminals:

```sql
-- If you are inside a transaction block, exit it first:
ROLLBACK;

-- Then delete the demo tenancies and waitlist entries we inserted.
-- (These deletes only touch rows whose start_date matches the session window
--  used in this guide, so they will not affect Portfolio 1 seed data.)
DELETE FROM rent_instalment
 WHERE tenancy_id IN (
     SELECT tenancy_id FROM tenancy
      WHERE start_date = DATE '<session_start>'
 );

DELETE FROM tenancy
 WHERE start_date = DATE '<session_start>';

DELETE FROM waitlist_entry
 WHERE room_type_id = <room_type_id>;
```

> **Important:** always `ROLLBACK` any open transaction in **both** terminals
> before running the DELETEs, otherwise the DELETE in one terminal will block
> waiting for the lock held by the other terminal.

[paste real output here]

---

# PART A: THE BUG - both students see one room left and both try to book it

## What we are showing

We **deliberately** use a **buggy** version of the free-room lookup that does
**NOT** use `FOR UPDATE`. Both terminals run the lookup, both see the **same**
free room, and both then try to INSERT a tenancy for it.

With the buggy lookup, one of two things can happen:

- **Scenario A1 (lost update avoided by accident):** both INSERTs target the
  same room and the same session window. The `btree_gist` EXCLUDE constraint
  from Portfolio 1 (`tenancy_no_room_overlap`) catches the second commit with
  `ERROR: conflicting key value violates exclusion constraint`. Data integrity
  is preserved, but the second student sees a confusing database error.
- **Scenario A2 (true double-booking bug):** if the two INSERTs target
  **different** session windows on the same room, both succeed and the room is
  now double-booked across two non-overlapping sessions. That is *not* a
  conflict, but it is also not what either student expected if they had agreed
  to share information.

In this demo we use the **same** session window in both terminals, so you will
see **Scenario A1**: the exclusion constraint catches the second commit. That
is the data-integrity safety net - but it is **not a fix**, because the second
student still has to retry and gets a database error instead of a polite
"that room is taken, here is another one" response.

## Setup (run once in Terminal 1)

Pick `<room_type_id>`, `<session_start>`, `<session_end>`, `<tenant1_id>`,
`<tenant2_id>` from the queries above.

Also run this so you can see the room both terminals are about to grab:

```sql
-- Show the one free room both terminals will see:
SELECT r.room_id, r.room_code, r.floor
  FROM room r
 WHERE r.room_type_id = <room_type_id>
   AND NOT EXISTS (
       SELECT 1 FROM tenancy t
        WHERE t.room_id = r.room_id
          AND t.status <> 'cancelled'
          AND daterange(t.start_date, t.end_date)
              && daterange(DATE '<session_start>', DATE '<session_end>')
   )
 ORDER BY r.room_id
 LIMIT 1;
```

[paste real output here]

Write down the `<room_id>` value returned. **Both** terminals will see this
same room because of `ORDER BY r.room_id LIMIT 1`.

## Terminal 1 - the buggy lookup, no lock

Type these commands **one at a time** into Terminal 1, pressing Enter after
each:

1. Begin the transaction at the default isolation level (READ COMMITTED):

   ```sql
   BEGIN;
   SET LOCAL default_transaction_isolation = 'read committed';
   ```

2. Run the **buggy** free-room lookup (no `FOR UPDATE`):

   ```sql
   SELECT r.room_id, r.room_code
     FROM room r
    WHERE r.room_type_id = <room_type_id>
      AND NOT EXISTS (
          SELECT 1 FROM tenancy t
           WHERE t.room_id = r.room_id
             AND t.status <> 'cancelled'
             AND daterange(t.start_date, t.end_date)
                 && daterange(DATE '<session_start>', DATE '<session_end>')
      )
    ORDER BY r.room_id
    LIMIT 1;
   ```

   **What to expect:** one row, with the same `<room_id>` you wrote down.

   [paste real output here]

3. **Stop here.** Do NOT INSERT yet. Leave Terminal 1's transaction open and
   switch to Terminal 2.

## Terminal 2 - sees the SAME free room

Type these into Terminal 2:

1. Begin a transaction:

   ```sql
   BEGIN;
   SET LOCAL default_transaction_isolation = 'read committed';
   ```

2. Run the **same buggy** lookup:

   ```sql
   SELECT r.room_id, r.room_code
     FROM room r
    WHERE r.room_type_id = <room_type_id>
      AND NOT EXISTS (
          SELECT 1 FROM tenancy t
           WHERE t.room_id = r.room_id
             AND t.status <> 'cancelled'
             AND daterange(t.start_date, t.end_date)
                 && daterange(DATE '<session_start>', DATE '<session_end>')
      )
    ORDER BY r.room_id
    LIMIT 1;
   ```

   **What to expect:** the SAME `<room_id>` Terminal 1 saw. This is the bug:
   both transactions read "this room is free" without locking it, so both
   believe they can book it.

   [paste real output here]

3. **Stop here.** Switch back to Terminal 1.

## Terminal 1 - INSERT and COMMIT

1. Back in Terminal 1, insert the tenancy for tenant 1:

   ```sql
   INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,
                        annual_rent_ngn, status, created_at)
   SELECT <room_id>, <tenant1_id>, DATE '<session_start>', DATE '<session_end>',
          rt.annual_rent_ngn, 'active', now()
     FROM room_type rt
     JOIN room r ON r.room_type_id = rt.room_type_id
    WHERE r.room_id = <room_id>;
   ```

   **What to expect:** `INSERT 0 1`.

   [paste real output here]

2. Commit:

   ```sql
   COMMIT;
   ```

   **What to expect:** `COMMIT`.

   [paste real output here]

## Terminal 2 - INSERT and try to COMMIT

1. Back in Terminal 2, insert the tenancy for **tenant 2** on the **same**
   room and **same** session window:

   ```sql
   INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,
                        annual_rent_ngn, status, created_at)
   SELECT <room_id>, <tenant2_id>, DATE '<session_start>', DATE '<session_end>',
          rt.annual_rent_ngn, 'active', now()
     FROM room_type rt
     JOIN room r ON r.room_type_id = rt.room_type_id
    WHERE r.room_id = <room_id>;
   ```

   **What to expect:** `INSERT 0 1`. The INSERT itself succeeds **inside
   Terminal 2's transaction** because the EXCLUDE constraint is checked at
   COMMIT time for deferrable-style GiST exclusions, and even at INSERT time
   PostgreSQL only sees Terminal 1's committed row if Terminal 1 has already
   COMMITted. Since Terminal 1 already COMMITted in the previous step, you
   **may** instead see the exclusion error here directly - that depends on
   PostgreSQL's timing. Either way, the next step (COMMIT) is where the
   conflict is certain to surface.

   [paste real output here]

2. Try to commit:

   ```sql
   COMMIT;
   ```

   **What to expect (Scenario A1):** an error similar to:

   ```
   ERROR:  conflicting key value violates exclusion constraint "tenancy_no_room_overlap"
   DETAIL:  Key (room_id, daterange(start_date, end_date))=(<room_id>, [<session_start>,<session_end>)) conflicts with existing key (<room_id>, [<session_start>,<session_end>)).
   ```

   This is the `btree_gist` EXCLUDE constraint from Portfolio 1 catching the
   double-booking at COMMIT time. The transaction is aborted.

   [paste real output here]

## Discussion of Part A

- **The bug:** both terminals read "this room is free" because neither
  acquired a lock on the room row. PostgreSQL's READ COMMITTED isolation level
  lets each statement see the latest committed data, so Terminal 2's SELECT saw
  no tenancy on that room (because Terminal 1 had not yet committed).
- **The safety net:** the `tenancy_no_room_overlap` EXCLUDE constraint
  prevented data corruption - the second transaction was aborted.
- **The bad UX:** the second student saw a confusing database error and had no
  idea their booking failed until they tried to COMMIT. There was no polite
  "that room is taken, try another one" response, and no automatic retry.
- **What we need:** a way to make Terminal 2 **block** until Terminal 1 has
  committed (so Terminal 2's lookup re-evaluates after Terminal 1's COMMIT), or
  to **skip** the locked room and grab a different one. Part B leans on the
  safety net; Part C does the right thing.

---

# PART B: FIX 1 - the exclusion constraint rejects the second booking

## What we are showing

Part A and Part B use **the same SQL**. The difference is the **framing**: in
Part B we explicitly lean on the `tenancy_no_room_overlap` EXCLUDE constraint
as the **first line of defence** against double-booking. We force a clean
ordering: Terminal 1 commits **first**, then Terminal 2 tries to commit and
gets the exclusion error.

This is a **data-integrity fix**, not a **UX fix**. The second student still
gets a database error. But it proves that even with no application-level
locking, the schema from Portfolio 1 guarantees no two tenancies can overlap
on the same room.

## Setup (run once in Terminal 1)

Run the **RESET between demos** SQL above in **both** terminals first, so
Part A's test data is gone. Then re-confirm the free room is back:

```sql
SELECT r.room_id, r.room_code
  FROM room r
 WHERE r.room_type_id = <room_type_id>
   AND NOT EXISTS (
       SELECT 1 FROM tenancy t
        WHERE t.room_id = r.room_id
          AND t.status <> 'cancelled'
          AND daterange(t.start_date, t.end_date)
              && daterange(DATE '<session_start>', DATE '<session_end>')
   )
 ORDER BY r.room_id
 LIMIT 1;
```

[paste real output here]

Confirm the `<room_id>` is the same one you used in Part A.

## Terminal 1 - INSERT and COMMIT first

1. Begin, look up the room (you can re-use the buggy lookup or just use the
   `<room_id>` you already know), INSERT, COMMIT - all in sequence:

   ```sql
   BEGIN;

   INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,
                        annual_rent_ngn, status, created_at)
   SELECT <room_id>, <tenant1_id>, DATE '<session_start>', DATE '<session_end>',
          rt.annual_rent_ngn, 'active', now()
     FROM room_type rt
     JOIN room r ON r.room_type_id = rt.room_type_id
    WHERE r.room_id = <room_id>;

   COMMIT;
   ```

   **What to expect:** `BEGIN`, `INSERT 0 1`, `COMMIT`. Terminal 1 has now
   booked the room.

   [paste real output here]

## Terminal 2 - INSERT, then try to COMMIT

1. Now switch to Terminal 2 and try to book the **same** room for tenant 2:

   ```sql
   BEGIN;

   INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,
                        annual_rent_ngn, status, created_at)
   SELECT <room_id>, <tenant2_id>, DATE '<session_start>', DATE '<session_end>',
          rt.annual_rent_ngn, 'active', now()
     FROM room_type rt
     JOIN room r ON r.room_type_id = rt.room_type_id
    WHERE r.room_id = <room_id>;
   ```

   **What to expect:** since Terminal 1 has already COMMITted, PostgreSQL now
   sees the existing tenancy on that room. You will likely see the exclusion
   constraint error **immediately** at INSERT time:

   ```
   ERROR:  conflicting key value violates exclusion constraint "tenancy_no_room_overlap"
   DETAIL:  Key (room_id, daterange(start_date, end_date))=(<room_id>, [<session_start>,<session_end>)) conflicts with existing key (<room_id>, [<session_start>,<session_end>)).
   ```

   If instead the INSERT appeared to succeed (returned `INSERT 0 1`), the
   conflict will surface at COMMIT - see the next step.

   [paste real output here]

2. Try to commit (skip this step if the INSERT already errored - your
   transaction is already aborted):

   ```sql
   COMMIT;
   ```

   **What to expect:** if the INSERT errored, `COMMIT` will report
   `ROLLBACK` (PostgreSQL's way of telling you the aborted transaction was
   rolled back at COMMIT time). If the INSERT succeeded, COMMIT will fail with
   the exclusion error shown above.

   [paste real output here]

## Discussion of Part B

- The `tenancy_no_room_overlap` EXCLUDE constraint from Portfolio 1 is a
  **last-resort data-integrity guarantee**. It uses the `btree_gist` extension
  to index both the scalar `room_id` and the `daterange(start_date, end_date)`
  in a single GiST index, and it refuses any new row whose `(room_id, daterange)`
  pair overlaps an existing row's.
- This protects the database from ever containing two overlapping tenancies on
  the same room, **no matter how badly the application code races**.
- But it is **not a UX fix**: the second student gets a database error message
  that talks about "exclusion constraint tenancy_no_room_overlap" - a phrase
  that means nothing to a student trying to book a lodge.
- The right application-level fix is to make Terminal 2 **block** until
  Terminal 1 has committed, or to **skip** the room Terminal 1 has locked and
  grab a different one. That is Part C.

---

# PART C: FIX 2 - SELECT FOR UPDATE SKIP LOCKED

## What we are showing

`SELECT ... FOR UPDATE` acquires a row-level lock on the chosen room. Any
**other** transaction that tries to `SELECT ... FOR UPDATE` the same row
**blocks** until the first transaction commits or rolls back.

`SELECT ... FOR UPDATE SKIP LOCKED` goes one step further: instead of
blocking, it **skips** the locked row and moves on to the next one in the
`ORDER BY`. If there is another free room of the same type, Terminal 2 gets
it. If there is not, Terminal 2 gets an empty result - which is exactly what
`reserve_room()` uses to decide "no free room, add the tenant to the
waitlist".

This is the right tool for the "rent rush" workload at the start of an
academic session: hundreds of students hitting the same room type at once.
You do not want them all to queue behind one transaction; you want each of
them to grab a **different** free room in parallel.

> **Setup requirement for Part C:** pick a `<room_type_id>` that has **at
> least 2 free rooms** for the session window. Re-run the "Find candidate room
> types" query above and pick a different room type if your Part A/B room type
> has only one free room.

## Setup (run once in Terminal 1)

Run the **RESET between demos** SQL in both terminals first. Then confirm
there are **at least 2** free rooms of your chosen room type:

```sql
SELECT r.room_id, r.room_code, r.floor
  FROM room r
 WHERE r.room_type_id = <room_type_id>
   AND NOT EXISTS (
       SELECT 1 FROM tenancy t
        WHERE t.room_id = r.room_id
          AND t.status <> 'cancelled'
          AND daterange(t.start_date, t.end_date)
              && daterange(DATE '<session_start>', DATE '<session_end>')
   )
 ORDER BY r.room_id;
```

[paste real output here]

Write down the **first two** `room_id` values - call them `<room_A>` (lowest
`room_id`) and `<room_B>` (next `room_id`). Terminal 1 will lock `<room_A>`;
Terminal 2 will skip it and grab `<room_B>`.

## Terminal 1 - lock room A

1. Begin a transaction:

   ```sql
   BEGIN;
   ```

2. Lock the first free room with `FOR UPDATE` (plain, not SKIP LOCKED - we
   want to actually lock it):

   ```sql
   SELECT r.room_id, r.room_code
     FROM room r
    WHERE r.room_type_id = <room_type_id>
      AND NOT EXISTS (
          SELECT 1 FROM tenancy t
           WHERE t.room_id = r.room_id
             AND t.status <> 'cancelled'
             AND daterange(t.start_date, t.end_date)
                 && daterange(DATE '<session_start>', DATE '<session_end>')
      )
    ORDER BY r.room_id
    LIMIT 1
    FOR UPDATE OF r;
   ```

   **What to expect:** one row, `<room_A>`. Terminal 1 now holds a row-level
   lock on `<room_A>` until it COMMITs or ROLLBACKs.

   [paste real output here]

3. **Stop here.** Do NOT INSERT or COMMIT yet. Switch to Terminal 2.

## Terminal 2 - SKIP LOCKED, grab room B

1. Begin a transaction:

   ```sql
   BEGIN;
   ```

2. Run the lookup with `FOR UPDATE SKIP LOCKED`:

   ```sql
   SELECT r.room_id, r.room_code
     FROM room r
    WHERE r.room_type_id = <room_type_id>
      AND NOT EXISTS (
          SELECT 1 FROM tenancy t
           WHERE t.room_id = r.room_id
             AND t.status <> 'cancelled'
             AND daterange(t.start_date, t.end_date)
                 && daterange(DATE '<session_start>', DATE '<session_end>')
      )
    ORDER BY r.room_id
    LIMIT 1
    FOR UPDATE OF r SKIP LOCKED;
   ```

   **What to expect:** one row, `<room_B>` - **not** `<room_A>`. Terminal 1's
   lock on `<room_A>` caused the `SKIP LOCKED` clause to skip past it and
   return the next free room instead. Terminal 2 now holds a row-level lock
   on `<room_B>`. **No blocking occurred.**

   [paste real output here]

3. **Stop here.** Switch back to Terminal 1.

## Terminal 1 - INSERT tenancy on room A, COMMIT

1. Back in Terminal 1, insert the tenancy for tenant 1 on `<room_A>`:

   ```sql
   INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,
                        annual_rent_ngn, status, created_at)
   SELECT <room_A>, <tenant1_id>, DATE '<session_start>', DATE '<session_end>',
          rt.annual_rent_ngn, 'active', now()
     FROM room_type rt
     JOIN room r ON r.room_type_id = rt.room_type_id
    WHERE r.room_id = <room_A>;
   ```

   **What to expect:** `INSERT 0 1`.

   [paste real output here]

2. Commit:

   ```sql
   COMMIT;
   ```

   **What to expect:** `COMMIT`. Terminal 1's lock on `<room_A>` is released.

   [paste real output here]

## Terminal 2 - INSERT tenancy on room B, COMMIT

1. Back in Terminal 2, insert the tenancy for tenant 2 on `<room_B>`:

   ```sql
   INSERT INTO tenancy (room_id, tenant_id, start_date, end_date,
                        annual_rent_ngn, status, created_at)
   SELECT <room_B>, <tenant2_id>, DATE '<session_start>', DATE '<session_end>',
          rt.annual_rent_ngn, 'active', now()
     FROM room_type rt
     JOIN room r ON r.room_type_id = rt.room_type_id
    WHERE r.room_id = <room_B>;
   ```

   **What to expect:** `INSERT 0 1`.

   [paste real output here]

2. Commit:

   ```sql
   COMMIT;
   ```

   **What to expect:** `COMMIT`. **Both** students got a room, with **no**
   database error, **no** double-booking, and **no** waiting.

   [paste real output here]

## What happens when there is NO second free room?

If you repeat Part C with a `<room_type_id>` that has **only one** free room,
Terminal 2's `SELECT ... FOR UPDATE SKIP LOCKED` returns **zero rows** (it
skips the only free room because Terminal 1 has locked it, and there is no
other free room to return). That empty result is the signal that
`reserve_room()` uses to add the tenant to the waitlist instead.

To see this, run the same setup as Part C but pick a room type with only one
free room, and at Terminal 2 step 2 you will see:

```
 room_id | room_code
---------+-----------
(0 rows)
```

[paste real output here]

That empty result is exactly what `reserve_room()`'s inner SELECT returns
when there is no unlocked free room, which is why the function then falls
through to the `INSERT INTO waitlist_entry` branch and returns
`outcome='waitlisted'`.

## Discussion of Part C

- `FOR UPDATE` alone would have made Terminal 2 **block** until Terminal 1
  committed, then re-evaluate the lookup. That is correct but it serialises
  the rent rush: every student queues behind the one in front. With hundreds
  of concurrent bookers, the queue becomes unacceptable.
- `FOR UPDATE SKIP LOCKED` is the PostgreSQL feature purpose-built for
  work-queue / "rent rush" workloads. Each concurrent caller takes a
  **different** row and proceeds in parallel. Callers that find no unlocked
  row get an empty result and can be routed to the waitlist.
- The `reserve_room()` function in `reserve_room.sql` uses `FOR UPDATE OF r`
  (plain). For an even higher-throughput version you would change it to
  `FOR UPDATE OF r SKIP LOCKED` and let the waitlist branch handle the "no
  unlocked free room" case. Both are correct; `SKIP LOCKED` is friendlier
  under load.
- This is the **right application-level fix** for the race: no database error,
  no double-booking, no waiting when there is another free room, and a clean
  waitlist fallback when there is not.

---

## What to screenshot for the LMS

For each Part (A, B, C), capture:

1. The setup query output (free-room count + chosen values).
2. The Terminal 1 prompt showing each step's command and its output.
3. The Terminal 2 prompt showing each step's command and its output.
4. The final state of `tenancy` after each Part:

   ```sql
   SELECT tenancy_id, room_id, tenant_id, start_date, end_date, status
     FROM tenancy
    WHERE start_date = DATE '<session_start>'
    ORDER BY tenancy_id;
   ```

Paste each captured output into the matching `[paste real output here]`
placeholder above so the markdown file you submit is a single self-contained
record of what you did and what PostgreSQL did in response.

---

## Git commit (run after pasting real outputs)

```bash
cd /workspaces/<your-repo>
git add portfolio-3-transactions-concurrency/race_condition_demo.md
git commit -m "P3: race condition demo in two terminals - bug, exclusion fix, FOR UPDATE SKIP LOCKED fix"
```
