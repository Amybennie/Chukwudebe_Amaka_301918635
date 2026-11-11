# Portfolio 5 - Distributed and Cloud Database Exercise

**Student:** Amaka Benedicta Chukwudebe
**Matric number:** 2026/A/MIT/0517
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 - Advanced Database Systems
**Academic session:** 2026/2027, First Semester (September Cohort 2026)
**Case study:** CampusNest - Private Student Accommodation Booking

---

## Study sessions this portfolio covers

| Session | Title | Where it shows up in P5 |
|---------|-------|--------------------------|
| **Study Session 2** | Distributed Database System - replication, CAP theorem, consistency models, BASE vs ACID | `partition.sql` (distributed-DB-style partitioning), `replication_demo.sh` / `replication_setup.md` (primary + streaming read replica, async vs sync replication, read-only transaction boundary), `cloud_architecture.md` Section C (CAP analysis), Section D (sync vs async trade-off) |
| **Study Session 3** | Big Data and Cloud Database Systems - cloud DB architecture, data warehouse, database security | `cloud_architecture.md` Section A (Nigerian cloud architecture, CDN, object storage, backups), Section E (rush handling with PgBouncer, materialised views, autoscaling), Section F (sharding vs partitioning) |
| **Study Session 6** | Data Security and Data Privacy - NDPA 2023, data privacy best practices | `cloud_architecture.md` Section B (NDPA 2023 compliance, data residency in Nigeria, encryption at rest/in transit, RLS, audit logging, 72h breach notification, data subject rights), `replication_setup.md` (peer login over the Unix socket, no passwords stored, replica is read-only) |

---

## What this portfolio demonstrates (plain English)

CampusNest stores rent instalments for thousands of tenants across UNILAG,
YABATECH, LASU, and UNN. Portfolio 1's bulk generator created over 100,000
`rent_instalment` rows spanning three academic years. A single flat table
that size becomes painful to back up, archive, and query by date. Portfolio
5 fixes that and then takes the database into the cloud, in five moves:

1. **Partitioning of `rent_instalment` by academic session** (`partition.sql`).
   The `PARTITION BY RANGE (due_date)` parent gets one partition per session
   (1 Sept to 1 Sept), created in a loop that covers every due date in the
   data plus the next session, and a DEFAULT partition that stays empty (the
   script prints its row count to prove it). The FK to tenancy, Portfolio 1's
   instalment-sum trigger and the indexes are recreated on the parent. A
   query for the current session reads only that session's partition
   (partition pruning, shown with EXPLAIN), and a finished session can be
   DETACHed and archived without touching live data. Instalments fall due in
   Sept, Jan, Mar and May, so monthly partitions would be mostly empty.

2. **A streaming read replica** (`replication_demo.sh`, explained in `replication_setup.md`). On the same
   Codespace, a second PostgreSQL data directory at
   `/var/lib/postgresql/16/ro` is built from `pg_basebackup` and started
   with `pg_ctl` on port 5433. It streams WAL from the primary on port 5432
   through a physical replication slot. The room-search website reads from
   the replica (read-only); writes (bookings, rent payments, maintenance
   tickets) go to the primary. The guide proves the replica is in recovery,
   proves it rejects writes (`ERROR: cannot execute INSERT in a read-only
   transaction`), and proves a row inserted on the primary appears on the
   replica within seconds.

3. **A Nigerian cloud architecture with NDPA 2023 compliance**
   (`cloud_architecture.md`). The primary, replica, MongoDB replica set
   (maintenance tickets from Portfolio 4), S3-compatible object storage
   (ticket photos), and nightly backups ALL live in a Nigerian region so
   no personal data crosses the border. The document maps every NDPA 2023
   obligation (lawful basis, data minimisation, storage limitation,
   security safeguards, 72-hour breach notification, data subject rights)
   to a specific technical control (encryption at rest + in transit, row-
   level security, `pgaudit` audit logging, least-privilege roles, a
   `forget_tenant()` erasure procedure that respects the 7-year tax
   retention).

4. **CAP theorem trade-offs.** Bookings are **CP** - a write either commits
   durably on the primary or fails; we never accept a stale write that
   could lose a booking. Maintenance-ticket reads off the MongoDB replica
   set are **AP-ish / eventually consistent** - a student can tolerate
   seeing a ticket status that is five seconds stale. The PostgreSQL
   primary+replica is CP for writes and eventually consistent for reads off
   the replica (replication lag).

5. **Start-of-session rush handling.** When new rooms open at the start of
   every academic session, thousands of students hit the room-search page
   at once. Seven tactics absorb the spike: read/write splitting (reads to
   the replica), PgBouncer transaction-mode pooling, `SELECT ... FOR UPDATE
   SKIP LOCKED` (from Portfolio 3) so concurrent reservations do not block
   each other, a per-minute materialised view of "free rooms per lodge per
   session" served from the replica, the waitlist as a pressure valve when
   a room type sells out, autoscaling a second read replica before the
   rush, and token-bucket rate limiting per tenant on the booking endpoint.

---

## Prerequisite

**Portfolio 1 must be run first.** Portfolio 1's `schema.sql` creates the
nine CampusNest tables (`lodge`, `room_type`, `room`, `tenant`,
`guarantor`, `tenancy`, `rent_instalment`, `waitlist_entry`,
`maintenance_ticket`) and Portfolio 1's `bulk_generator.py` populates
`rent_instalment` with 100,000+ rows spanning three academic years.
`partition.sql` converts that existing data into one partition per academic session - if
the data does not exist, there is nothing to partition and `run_p5.sh` will
stop with a clear error.

```bash
# From the repository root, in a Codespace:
cd portfolio-1-database-design && ./run_p1.sh
cd ../portfolio-5-distributed-cloud && ./run_p5.sh
```

---

## Codespaces conventions used (recap)

- The Codespace user can `sudo` only as root, so every `psql` that must
  run as the `postgres` OS user uses `sudo runuser -u postgres -- psql ...`.
  **NEVER** `sudo -u postgres` - it fails in Codespaces.
- PostgreSQL 16 config dir: `/etc/postgresql/16/main/`.
- `pg_ctl` binary: `/usr/lib/postgresql/16/bin/pg_ctl`.
- TCP logins need a password, so all local `psql` connections go through
  the Unix socket `host=/var/run/postgresql`.
- A replica made with `pg_basebackup` needs its own `postgresql.conf`
  (copied from the primary by `pg_basebackup`, then edited to set
  `port = 5433`, `hot_standby = on`). The `pg_hba.conf` trust lines MUST
  go at the TOP of the file (first match wins).
- We do **not** use `postgres_fdw`.
- All dates are generated relative to today inside the scripts, so nothing
  in this portfolio expires.

---

## Exact Codespaces commands to run this portfolio

```bash
cd portfolio-5-distributed-cloud
bash run_p5.sh 2>&1 | tee p5_output.log
```

`run_p5.sh` partitions `rent_instalment`, then runs `replication_demo.sh`,
which builds the read replica on port 5433, proves it works and saves
`replication_output.log`. Nothing needs to be typed. Codespaces has no
systemd, so the replica is started with
`/usr/lib/postgresql/16/bin/pg_ctl` and the primary keeps running the whole
time (PostgreSQL 16's defaults already have `wal_level = replica`).

---

## Evidence to capture

1. `p5_output.log`: the rows per partition (DEFAULT = 0) and the EXPLAIN
   showing `Subplans Removed` (only the current session's partition read).
2. `replication_output.log`: who is who (5432 PRIMARY, 5433 REPLICA), the
   write rejected on the replica, the ticket written on the primary
   appearing on the replica, and `pg_stat_replication` with the lag.
3. `cloud_architecture.md`: the Nigerian-region design, NDPA 2023, CAP.

---

## File inventory

| File | Purpose |
|------|---------|
| `README.md` | This file - study-session map, plain-English explanation, run commands, screenshot checklist, git commit command, file inventory. |
| `run_p5.sh` | Runner: checks Portfolio 1 data, runs `partition.sql`, prints rows per partition, then runs `replication_demo.sh` (output saved to `replication_output.log`). |
| `partition.sql` | Converts `rent_instalment` from a flat heap into a monthly `PARTITION BY RANGE (due_date)` table: renames the old table, creates the partitioned parent with PK `(instalment_id, due_date)`, generates 36 monthly partitions relative to today (24 months ago to 12 months ahead) plus a DEFAULT partition, copies the old data in (auto-routed by `due_date`), recreates the FK to `tenancy` and the `instalment_sum` trigger on the parent (PG 16 propagates both to every partition), recreates the secondary indexes on the parent (PG 16 propagates), drops the old table, and lists the partitions + per-month row distribution. |
| `replication_demo.sh` | One script that builds the read replica (pg_basebackup -R, minimal conf on port 5433, hba/ident copied, chmod 700, pg_ctl start) and proves it works: who is who, write rejected on the replica, row written on the primary arrives, lag and `pg_stat_replication`. |
| `replication_setup.md` | Explains each step of `replication_demo.sh` and why it is done that way in Codespaces. |
| `cloud_architecture.md` | A ~1,500-word cloud architecture document. Section A: ASCII architecture diagram with all data stores in a Nigerian region. Section B: NDPA 2023 compliance (lawful basis, data minimisation, storage limitation, security safeguards, 72h breach notification, data subject rights) mapped to specific technical controls (encryption at rest + in transit, RLS, `pgaudit`, least-privilege roles, `forget_tenant()`). Section C: CAP theorem analysis (CP for bookings, AP-ish for maintenance reads, MongoDB tunable consistency). Section D: sync vs async replication trade-off + the per-transaction `SET LOCAL synchronous_commit = on` pattern for critical writes. Section E: seven tactics for the start-of-session rush (read/write split, PgBouncer, `SKIP LOCKED`, materialised view, waitlist, autoscale replicas, rate limiting). Section F: sharding vs partitioning note. |

---

## Honest results policy

Every result placeholder in this portfolio is the literal string
`[paste real output here]` until the student runs the work and pastes the
real output. No output, timing, or screenshot in this portfolio has been
fabricated. The partition list, row counts, `pg_stat_replication` output,
`pg_is_in_recovery()` output, the read-only-transaction error, and the
replica row-appearance check are all captured by running the documented
commands in a Codespace and pasting what the terminal actually returned.
