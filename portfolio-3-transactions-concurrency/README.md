# Portfolio 3 - Transactions and Concurrency

**Student:** Amaka Benedicta Chukwudebe
**Matric number:** 2026/A/MIT/0517
**Programme:** Master of Information Technology
**Institution:** Miva Open University
**Course:** MIT 8103 - Advanced Database Systems
**Academic session:** 2026/2027, First Semester (September Cohort 2026)
**Case study:** CampusNest - Private Student Accommodation Booking

---

## Study sessions covered

This portfolio demonstrates the practical material from **two** course-note
study sessions:

| Study session | Topics demonstrated here |
|---------------|--------------------------|
| **Study Session 1 - Review of Traditional Relational Databases and Advanced Concepts** | The ACID properties. `reserve_room()` is one atomic transaction whose caller controls `COMMIT`/`ROLLBACK`. The COMMIT demo shows **Atomicity + Durability**; the ROLLBACK demo shows **Atomicity** alone; the exclusion constraint from Portfolio 1 is the **Consistency** guarantee; the row-level `FOR UPDATE` lock and the isolation levels show **Isolation**. |
| **Study Session 2 - Distributed Database System** | Consistency models and the BASE vs ACID contrast. The three isolation levels (READ COMMITTED, REPEATABLE READ, SERIALIZABLE) are the spectrum of consistency the application can choose from; the race condition demo shows what happens when consistency is relaxed; the deadlock demo shows the cost of strong isolation under contention. CAP is touched on in the race-condition discussion (a single-node PostgreSQL is CP - it prefers consistency over availability when partitioned, but this portfolio runs on one node so the partition case is only discussed, not demonstrated). |

---

## Plain-English explanation of what this portfolio demonstrates

CampusNest's hardest concurrency problem is the **rent rush**: when bookings
open for the next academic session, hundreds of students ask for the same
room type at the same moment. If two students both see "bed free" and both
click "Book", a naive system gives the same bed to both.

**Main fix used in this portfolio: the exclusion constraint.**
`tenancy_no_room_overlap` (Portfolio 1) says no two non-cancelled tenancies
on one bed-space may have overlapping date ranges. The database itself
enforces it, so no application bug or race can ever double-book a bed.

1. **`reserve_room.sql`** - `reserve_room(tenant, room_type)` books a free bed
   for the next session (1 Sept to 1 Sept) and records the first instalment
   as paid, or puts the student on the waitlist. It picks the bed with
   `FOR UPDATE SKIP LOCKED`, so a second student at the same moment gets the
   next free bed instead of waiting; the exclusion constraint is the safety
   net; the room_type row is locked before a waitlist position is given out,
   so two students never get the same position. It never commits itself: the
   caller COMMITs (payment succeeded) or ROLLs BACK (payment failed).
2. **`run_p3.sh`** - loads the function, runs the COMMIT demo and the
   ROLLBACK demo, then runs `run_race_demos.py`. No typing or second terminal
   is needed.
3. **`run_race_demos.py`** - opens two real database sessions (A and B, like
   two psql terminals) and runs six scenarios, saving the real output to
   `race_demos_output.log`:

   | Part | What happens | What it proves |
   |---|---|---|
   | 1 | Check-then-insert on a copy of the table with no constraint | Both students get the same bed (the bug) |
   | 2 | Same race on the real table | B waits for A, then the exclusion constraint refuses B (23P01) |
   | 3 | Both call `reserve_room()` at once | SKIP LOCKED gives them different beds, no waiting |
   | 4 | Part 1 again at SERIALIZABLE | PostgreSQL aborts B with 40001 |
   | 5 | READ COMMITTED vs REPEATABLE READ | A non-repeatable read, then a stable snapshot |
   | 6 | Two sessions update two instalments in opposite order | Deadlock detected (40P01); fix = lock rows in one fixed order |

   Every row it creates is removed at the end, so it can be re-run.
4. **`isolation_levels.sql`, `deadlock_demo.sql`, `race_condition_demo.md`** -
   the original two-terminal guides, kept for anyone who wants to repeat a
   part by hand (for example if the lecturer asks for a live demo).

---

## Prerequisite: Portfolio 1 must be run first

This portfolio depends on Portfolio 1's schema and seed data. Before running
anything here, Portfolio 1 must have:

- Created the `campusnest` database.
- Loaded the `btree_gist` extension (for the EXCLUDE constraints on
  `tenancy` and the `daterange` overlap checks).
- Created the 9 CampusNest tables: `lodge`, `room_type`, `room`, `tenant`,
  `guarantor`, `tenancy`, `rent_instalment`, `waitlist_entry`,
  `maintenance_ticket`.
- Loaded the seed data (lodges, room types, rooms, tenants, sample
  tenancies).

If Portfolio 1 has not been run yet, `run_p3.sh` will detect the missing
tables and abort with a clear message telling you to run Portfolio 1 first.

```bash
cd ../portfolio-1-database-design
./run_p1.sh
cd ../portfolio-3-transactions-concurrency
```

The Codespaces bootstrap (`setup.sh` at the repository root) must also have
been run once to install PostgreSQL 16 and create the `campusnest` database.

---

## Exact Codespaces commands

```bash
cd portfolio-3-transactions-concurrency
bash run_p3.sh 2>&1 | tee p3_output.log
```

Evidence files: `p3_output.log` (COMMIT and ROLLBACK demos plus everything
else) and `race_demos_output.log` (the six two-session scenarios).

---

## What to screenshot for the LMS submission

For each of the items below, capture the terminal output (text is fine -
screenshots are optional but the text must be readable) and paste it into
the matching `[paste real output here]` placeholder in the source file.
**Do not fabricate output.** If a demo did not produce the expected result,
write what actually happened and explain it.

| # | File | What to capture |
|---|------|-----------------|
| 1 | `run_p3.sh` | The `[1/7]` schema verification output (table counts). |
| 2 | `run_p3.sh` | The `[2/7]` reserve_room function load + `\df+` verification. |
| 3 | `run_p3.sh` | The `[3/7]` COMMIT demo output (before/after counts, the persisted tenancy + instalment). |
| 4 | `run_p3.sh` | The `[4/7]` ROLLBACK demo output (before/during/after counts, the empty result after rollback). |
| 5 | `isolation_levels.sql` | Three `[paste real output here]` blocks - one per isolation level, each showing Terminal 1 AND Terminal 2 outputs. |
| 6 | `deadlock_demo.sql` | Five `[paste real output here]` blocks - one per step, including both terminals for STEP 4 (the deadlock moment) and STEP 5 (aftermath), plus the retry block. |
| 7 | `race_condition_demo.md` | Three `[paste real output here]` blocks per Part (A, B, C) - Terminal 1 and Terminal 2 outputs for the setup, the lookup, the INSERT, and the COMMIT/ROLLBACK. Plus the final `tenancy` state query after each Part. |
| 8 | `reserve_room.sql` | The function source itself (already in the file - no paste needed). |

Paste each captured output into the source markdown / SQL file in the
matching `[paste real output here]` placeholder, then commit the updated
files to git. The LMS submission will reference these files in your private
GitHub repository.

---

## The exact git commit command

After pasting all real outputs into the `[paste real output here]`
placeholders, commit the portfolio:

```bash
cd /workspaces/<your-repo>
git add portfolio-3-transactions-concurrency/
git commit -m "P3: transactions and concurrency - reserve_room(), COMMIT/ROLLBACK, race condition, isolation levels, deadlock"
```

If you prefer to commit each file separately as you complete it:

```bash
cd /workspaces/<your-repo>
git add portfolio-3-transactions-concurrency/reserve_room.sql
git commit -m "P3: reserve_room() PL/pgSQL function with SELECT FOR UPDATE"

git add portfolio-3-transactions-concurrency/run_p3.sh
git commit -m "P3: run_p3.sh runner - schema verify, COMMIT/ROLLBACK demos, isolation + deadlock drivers"

git add portfolio-3-transactions-concurrency/race_condition_demo.md
git commit -m "P3: race condition demo in two terminals - bug, exclusion fix, FOR UPDATE SKIP LOCKED fix"

git add portfolio-3-transactions-concurrency/isolation_levels.sql
git commit -m "P3: isolation levels demo - READ COMMITTED, REPEATABLE READ, SERIALIZABLE"

git add portfolio-3-transactions-concurrency/deadlock_demo.sql
git commit -m "P3: two-session deadlock demo with retry pattern"

git add portfolio-3-transactions-concurrency/README.md
git commit -m "P3: README - study session map, commands, screenshot checklist, git commit"
```

---

## File inventory

| File | Type | Purpose |
|------|------|---------|
| `README.md` | Markdown | This file. Study session map, plain-English explanation, prerequisite, exact commands, screenshot checklist, git commit command, file inventory. |
| `run_p3.sh` | Bash script (executable) | One-shot runner. Verifies P1 schema, loads `reserve_room.sql`, runs COMMIT and ROLLBACK demos, runs `isolation_levels.sql` and `deadlock_demo.sql`, prints the race-condition message, cleans up. |
| `reserve_room.sql` | PL/pgSQL | The `reserve_room(tenant, room_type, [session_start], [first_instalment])` function. Atomically reserves a free room + first instalment, or waitlists the tenant. Uses `SELECT ... FOR UPDATE OF r` on the chosen room. The caller controls COMMIT/ROLLBACK. |
| `race_condition_demo.md` | Markdown guide | Three-part two-terminal guide: Part A (the bug - no lock), Part B (fix 1 - EXCLUDE constraint), Part C (fix 2 - `FOR UPDATE SKIP LOCKED`). The centerpiece of P3. |
| `isolation_levels.sql` | psql script | Demonstrates READ COMMITTED, REPEATABLE READ, and SERIALIZABLE in two terminals. Uses `\echo` + `\prompt` so Terminal 1 drives the demo and pauses while Terminal 2 commits its writes. |
| `deadlock_demo.sql` | psql script | Picks two `tenancy_id`s and prints the five-step instructions to produce a classic two-session deadlock in two terminals. Includes the retry pattern and an ACID-perspective discussion. |

---

## How the five files fit together

```
                 run_p3.sh
                     |
                     |-- [1/7] verify P1 schema
                     |-- [2/7] load  reserve_room.sql  -->  creates reserve_room()
                     |-- [3/7] COMMIT demo  (calls reserve_room, COMMIT)
                     |-- [4/7] ROLLBACK demo (calls reserve_room, ROLLBACK)
                     |-- [5/7] run    isolation_levels.sql  (interactive, 2 terminals)
                     |-- [6/7] run    deadlock_demo.sql     (prints instructions, 2 terminals)
                     |-- [7/7] point at race_condition_demo.md (MANUAL, 2 terminals)
                     '-- cleanup

  reserve_room.sql is also used by hand in race_condition_demo.md Part C
  (the student is asked to compare the buggy lookup with the function's
  SELECT FOR UPDATE).
```

Every demo that produces terminal output has `[paste real output here]`
placeholders. The honesty rule from the repository root applies: nothing is
fabricated. The student runs each demo, captures the real output, and pastes
it into the matching placeholder before committing.

---

## AI use declaration (per-portfolio note)

This portfolio folder was scaffolded with AI assistance (the AI tool was
used to draft the SQL, bash, and markdown files). The student's
responsibilities, per the CA brief Section 11, are:

1. Run `setup.sh` and Portfolio 1 first.
2. Run `./run_p3.sh` and follow the two-terminal guides manually.
3. Capture the real terminal output for every `[paste real output here]`
   placeholder.
4. Verify the function behaviour matches the documentation (e.g. that
   `SELECT FOR UPDATE` does block the second terminal, that the exclusion
   constraint does fire on the second commit, that SSI does abort the
   serializable transaction).
5. Correct any place where the real behaviour diverges from what the file
   predicted, and note the divergence in the file.
6. Be able to explain every script, every SQL statement, and every design
   choice if selected for the brief technical verification discussion
   (CA brief Section 8).

The full AI-use declaration goes into the final 2-3 page LMS documentation
file `Chukwudebe_Amaka_2026-A-MIT-0517_Documentation.pdf`, produced after
all five portfolios have been run.

---

## Next portfolio

```bash
cd ../portfolio-4-nosql && ./run_p4.sh
```
