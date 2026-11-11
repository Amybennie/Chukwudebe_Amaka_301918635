# Portfolio 4 - NoSQL and Advanced Data Models

**Student:** Amaka Benedicta Chukwudebe
**Matric number:** 2026/A/MIT/0517
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 - Advanced Database Systems
**Academic session:** 2026/2027, First Semester (September Cohort 2026)
**Case study:** CampusNest - Private Student Accommodation Booking

---

## Study sessions covered

This portfolio demonstrates the practical material from two course-note
study sessions:

| Study session | Topic | Where it shows up in this portfolio |
|---------------|-------|-------------------------------------|
| **Study Session 3 - Big Data and Cloud Database Systems** | Big data, cloud database systems, database security | MongoDB is a document database that scales horizontally to big-data volumes. The 42,000+ document maintenance_tickets collection is the volume benchmark for the big-data topic. MongoDB is also the canonical cloud-native database that Session 3 covers in its "cloud database systems" half. |
| **Study Session 5 - Emerging Trends in Database Systems** | Document databases, serverless databases, graph databases, knowledge graphs | The $jsonSchema validator with `additionalProperties:true` and per-category polymorphic fields is exactly the "emerging data models" departure from rigid relational schemas that Session 5 documents. The `sql_vs_nosql.md` write-up closes the loop on when each model fits. |

The session -> portfolio map is also documented in
`../docs/00_brief_summary.md`.

---

## What this portfolio demonstrates, in plain English

The CampusNest case study has a `maintenance_ticket` entity. Every ticket
records a complaint a student logged with their lodge: a leaking tap, a
sparking socket, a broken desk, a cockroach infestation, and so on. The
problem is that the four ticket **categories** (plumbing, electrical,
furniture, pest_control) each carry **different fields**:

- a **plumbing** ticket wants `affected_fixture` (tap/shower/toilet/pipe),
  `leak_present`, `water_shut_off_needed`;
- an **electrical** ticket wants `affected_appliance`
  (socket/light/ac/fan/breaker), `voltage_issue`, `spark_or_smoke`,
  `safety_hazard`;
- a **furniture** ticket wants `item_type` (bed/desk/chair/wardrobe/door),
  `damage_type`, `requires_replacement`;
- a **pest_control** ticket wants `pest_type`
  (cockroach/rodent/bedbug/mosquito/termite), `infestation_level`,
  `treatment_method`.

On top of that, every ticket accumulates:

- an **array of photos** (each with a URL, an upload timestamp, and a
  caption);
- an **array of status_history entries** (each a state transition:
  open -> in_progress -> resolved -> closed, with the actor and a note);
- an **array of technician_visits** (each with a visit_id, technician
  name, visited_at, findings, action_taken).

Modelling this in PostgreSQL has three painful options:

1. One `maintenance_ticket` table with **dozens of NULL columns** for the
   per-category fields. Most rows have most of those columns NULL. The
   schema becomes hard to read, hard to validate, and easy to mis-fill.
2. **Four tables**, one per category, plus a parent ticket table. Every
   query that lists mixed categories needs `UNION ALL` across the four
   children; every dashboard query now has 4-way joins.
3. An **EAV** (entity-attribute-value) pattern with `ticket_attribute`
   rows `(ticket_id, attr_name, attr_value)`. This destroys types and
   makes every query a self-join.

MongoDB sidesteps all three:

- the **common envelope** (ticket_id, lodge_id, lodge_name, room_code,
  category, reported_at, status, summary, status_history, photos,
  technician_visits) is enforced by a `$jsonSchema` validator;
- the **per-category polymorphic fields** are allowed through
  `additionalProperties:true` and are simply attached to the document;
- the **photos, status_history, and technician_visits arrays** are
  embedded **inside** the ticket document, so reading one ticket is a
  single document fetch instead of a 5-table JOIN in SQL.

The maintenance workload is **read-heavy on the "show me this ticket
with everything attached"** path: a lodge manager or technician opens a
ticket and wants the photos, the history, and the visits in one round
trip. That is exactly the workload MongoDB was designed for.

This portfolio therefore demonstrates:

1. **JSON Schema validation** on a MongoDB collection - the validator
   enforces the common envelope while leaving room for polymorphic
   per-category fields.
2. **Bulk seeding of 42,000+ documents** across the four categories with
   weighted distribution (plumbing and electrical more common).
3. **Three aggregation pipelines** answering real business questions:
   tickets per lodge per category; average resolution time per category;
   repeat problems per room (3+ same-category tickets in 90 days).
4. **Index demo** - COLLSCAN before a compound index is created, IXSCAN
   after, with `explain('executionStats')` for both.
5. **A SQL-vs-NoSQL comparison** (`sql_vs_nosql.md`) that argues for a
   hybrid architecture: PostgreSQL for the booking / tenancy / rent
   core (Portfolios 1-3), MongoDB for maintenance tickets (Portfolio 4).

---

## Where the 42,000 tickets come from

`run_p4.sh` exports the real non-cancelled tenancies from PostgreSQL
(tenant, lodge, bed-space, dates) and `seed.js` raises every ticket for a real
tenant, in the bed-space they rented, during their tenancy. Each ticket has
one consistent timeline (reported -> in progress -> resolved -> closed) and
its status is wherever that timeline has reached today, so nothing is dated
in the future. The index demo picks the lodge and category with the most
unfinished tickets right now. Its output is saved to `index_demo_output.log`.

## Codespaces commands to run it

These instructions assume `setup.sh` has already been run at the repo
root (it installs PostgreSQL 16 + MongoDB 8 and starts `mongod`).

```bash
# 1. Make sure mongod is running.
pgrep -x mongod || sudo runuser -u mongodb -- mongod --config /etc/mongod.conf --fork

# 2. From the repo root, enter the Portfolio 4 folder.
cd advanced-database-portfolio/portfolio-4-nosql

# 3. Make the runner executable (first time only).
chmod +x run_p4.sh

# 4. Run everything in one shot.
./run_p4.sh
```

`run_p4.sh` will:

1. ping `mongod` with `db.runCommand({ping:1})`;
2. drop the `campusnest_nosql` database (fresh start);
3. run `schema_validation.js`;
4. run `seed.js` (42,000+ documents);
5. print `db.maintenance_tickets.estimatedDocumentCount()`;
6. run `aggregations.js`;
7. run `index_demo.js` (BEFORE: COLLSCAN, AFTER: IXSCAN).

You can also run each JS file individually if you want to inspect one
step:

```bash
mongosh mongodb://127.0.0.1:27017/campusnest_nosql schema_validation.js
mongosh mongodb://127.0.0.1:27017/campusnest_nosql seed.js
mongosh mongodb://127.0.0.1:27017/campusnest_nosql aggregations.js
mongosh mongodb://127.0.0.1:27017/campusnest_nosql index_demo.js
```

Open an interactive shell any time with:

```bash
mongosh mongodb://127.0.0.1:27017/campusnest_nosql
```

---

## What to screenshot for the LMS submission

After running `./run_p4.sh`, take screenshots of:

1. **STEP 3 output** - the `listCollections` info showing the
   `$jsonSchema` validator on `maintenance_tickets`, plus the four valid
   example docs and the rejected invalid doc. This proves the validator
   is in force.
2. **STEP 5 output** - `db.maintenance_tickets.estimatedDocumentCount()`
   showing 40,000+ documents.
3. **STEP 6 output** - the three aggregation results (AGG-1, AGG-2,
   AGG-3). Each prints `printjson(...)` output.
4. **STEP 7 output** - the BEFORE (COLLSCAN) and AFTER (IXSCAN)
   `explain('executionStats')` summaries, plus the side-by-side
   comparison table at the end of `index_demo.js`.

Then paste the real terminal output into this README at every
`[paste real output here]` placeholder below, and commit.

---

## Honest results policy

Where real output would appear (explain plans, aggregation results,
timings, document counts produced by `seed.js`), this README and the JS
files use the literal placeholder:

```
[paste real output here]
```

Nothing is fabricated. The student must run the scripts and paste the
real output.

---

## Real output (paste after running)

### schema_validation.js

```
[paste real output here]
```

### seed.js - final document count

```
[paste real output here]
```

### aggregations.js

#### AGG-1: Tickets per lodge per category (flat matrix)

```
[paste real output here]
```

#### AGG-1: Tickets per lodge per category (nested view)

```
[paste real output here]
```

#### AGG-2: Average resolution time per category (days)

```
[paste real output here]
```

#### AGG-3: Repeat problems per bed-space (2+ same-category in 12 months)

```
[paste real output here]
```

### index_demo.js

#### BEFORE INDEX (COLLSCAN) - summarised executionStats

```
[paste real output here]
```

#### AFTER INDEX (IXSCAN) - summarised executionStats

```
[paste real output here]
```

#### Comparison table

```
[paste real output here]
```

---

## Git commit command

After pasting real output into this README and into `sql_vs_nosql.md`
(where applicable), commit and push:

```bash
git add advanced-database-portfolio/portfolio-4-nosql/
git commit -m "Portfolio 4: NoSQL MongoDB maintenance tickets (schema validator, 42k docs, aggregations, COLLSCAN->IXSCAN)"
git push
```

---

## File inventory

| File | Purpose |
|------|---------|
| `README.md` | This file - student header, study sessions covered, plain-English explanation, run commands, screenshot checklist, git commit, file inventory. |
| `run_p4.sh` | One-shot bash runner. Pings mongod, drops the database, runs the four JS files in order, prints clear step headers. |
| `schema_validation.js` | Creates `maintenance_tickets` with a `$jsonSchema` validator; inserts 4 valid per-category example docs and 1 invalid doc to prove the validator rejects it. |
| `seed.js` | Generates 42,000+ maintenance ticket documents across the four categories with weighted distribution, embedded photos / status_history / technician_visits, and per-category polymorphic fields. Bulk-inserts in batches of 1,000. |
| `aggregations.js` | Three aggregation pipelines: AGG-1 tickets per lodge per category; AGG-2 average resolution days per category; AGG-3 repeat problems per room in 90 days. |
| `index_demo.js` | Drops indexes, runs `explain('executionStats')` for a realistic query (COLLSCAN), creates the compound index `{lodge_id:1, status:1, category:1, reported_at:-1}`, runs `explain()` again (IXSCAN), prints a side-by-side comparison. |
| `sql_vs_nosql.md` | ~600-900 word comparison: when SQL wins, when NoSQL wins, the hybrid architecture chosen for CampusNest, and a side-by-side table for the maintenance-ticket use case. |

---

## Connection string (for reference)

```
mongodb://127.0.0.1:27017/campusnest_nosql
```

- host: `127.0.0.1`
- port: `27017`
- database: `campusnest_nosql`
- auth: none (dev Codespaces)

Start the server with `pgrep -x mongod || sudo runuser -u mongodb -- mongod --config /etc/mongod.conf --fork` (Codespaces has no systemd).
Check it with `mongosh --eval 'db.runCommand({ping:1})'`.
