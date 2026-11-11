# MIT 8103 - Advanced Database Systems Portfolio

**Student:** Amaka Benedicta Chukwudebe
**Matric number:** 2026/A/MIT/0517
**Programme:** Master of Information Technology
**Institution:** Miva Open University
**Course:** MIT 8103 - Advanced Database Systems
**Academic session:** 2026/2027, First Semester (September Cohort 2026)
**GitHub repository:** https://github.com/Amybennie/Chukwudebe_Amaka_301918635

---

## Case study

**Organisation:** CampusNest (simulated company)
**Business:** Private Student Accommodation Booking
**What it does:** CampusNest manages private off-campus student lodges near four Nigerian tertiary institutions:

| Code | Institution | Town |
|------|-------------|------|
| UNILAG | University of Lagos | Akoka, Lagos |
| YABATECH | Yaba College of Technology | Yaba, Lagos |
| LASU | Lagos State University | Ojo, Lagos |
| UNN | University of Nigeria, Nsukka | Nsukka, Enugu State |

**Users of the database**
- Students - browse lodges, reserve a room type, pay rent, sign a tenancy, log maintenance requests, and join a waitlist when a room type is sold out.
- Lodge managers - manage rooms, room types, rent, and maintenance turnaround.
- Finance officers - track rent collected vs outstanding per lodge.
- Maintenance technicians - receive and close maintenance tickets.
- CampusNest operations - monitor occupancy, waitlists, and the start-of-session rush when new rooms open.

**Major data stored**
- Lodges and their nearest school, address, and city.
- Room types (single, shared 2-person, shared 4-person) and annual rent in Naira.
- Lettable bed-spaces inside each lodge (a shared_4 room is four bed-spaces).
- Tenants (students) and their guarantors.
- Tenancies (room + tenant + start/end date) with no overlaps allowed.
- Rent instalments that must sum to no more than the annual rent.
- Waitlist entries for sold-out room types.
- Maintenance tickets (plumbing, electrical, furniture, pest control) with photos and status history.

**Key operations supported**
- Browse lodges and free rooms for the next academic session.
- Reserve a room of a chosen type; if none is free, join the waitlist.
- Pay annual rent in full or in instalments; failed payment cancels the reservation.
- Sign a tenancy and enforce no overlapping tenancies on the same room.
- Log, assign, and close maintenance tickets with status history.
- Report occupancy %, rent collected vs outstanding, overdue instalments, waitlist length, average days to fix a ticket.

---

## Repository layout

```
advanced-database-portfolio/
├── README.md                              <- you are here
├── setup.sh                               <- installs + starts PostgreSQL 16 and MongoDB 8 in Codespaces
├── collect_results.sh                     <- gathers every portfolio's real output into my_results.txt
├── CHANGES.md                             <- what was fixed after testing
├── docs/
│   ├── 00_brief_summary.md                <- CA summary + portfolio -> study session map
│   ├── REFERENCES.md
│   └── screenshots/README.md              <- list of evidence files
├── portfolio-1-database-design/           <- ER, 3NF, 9 tables, exclusion constraints, seed + 50k+ tenancy generator
├── portfolio-2-query-optimisation/        <- 7 queries, EXPLAIN ANALYZE before/after indexes
├── portfolio-3-transactions-concurrency/  <- reserve_room(), COMMIT/ROLLBACK, six two-session race demos
├── portfolio-4-nosql/                     <- MongoDB maintenance tickets, schema validation, aggregations, 40k docs
└── portfolio-5-distributed-cloud/         <- session partitions, scripted streaming replica, cloud arch (NDPA 2023, CBN, CAP)
```

Each portfolio folder has its own:
- `README.md` - exact Codespaces commands, what to screenshot, the git commit command, plain-English explanation, study session covered.
- `run_pN.sh` - one-shot runner for that portfolio.

---

## How to run it (in a GitHub Codespace)

```bash
bash setup.sh                       # once: PostgreSQL 16 + MongoDB 8, database, roles
for N in 1 2 3 4 5; do              # every portfolio, in order
  D=$(ls -d portfolio-$N-*)
  (cd "$D" && bash run_p$N.sh 2>&1 | tee p${N}_output.log)
done
bash collect_results.sh             # gathers the real outputs into my_results.txt
```

Codespaces notes (already handled by the scripts):
- There is no systemd, so PostgreSQL is started with `pg_ctlcluster` and MongoDB with `mongod --fork`; the read replica uses `/usr/lib/postgresql/16/bin/pg_ctl`.
- `sudo` works only as root, so commands that must run as the postgres user use `sudo runuser -u postgres -- ...`, never `sudo -u postgres`.
- All connections use the Unix socket `/var/run/postgresql` (peer login, no passwords).
- All dates are computed from today, so nothing expires.

## Evidence

Each runner saves its own output: `p1_output.log` ... `p5_output.log`, plus
`p2_timings.md`, `race_demos_output.log` (P3), `index_demo_output.log` (P4) and
`replication_output.log` (P5). See `docs/screenshots/README.md`. No output in
this repository was typed in by hand; every number comes from a real run.

## Fixes made after testing

`CHANGES.md` lists every problem found when the original AI-generated scripts
were tested in a Codespace-like environment, the fix, and the tested result.

---

## AI use declaration (filled in by student after running)

This is completed in the final documentation file
`Chukwudebe_Amaka_Documentation.pdf`, written after all five portfolios have
been run. It states:
1. The AI tool used.
2. What the AI tool was used for.
3. How the output was reviewed, corrected, tested, or verified by the student.

---

## References

See `docs/REFERENCES.md`.
