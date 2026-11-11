# SQL vs NoSQL - Choosing the Right Tool for Each CampusNest Workload

**Student:** Amaka Benedicta Chukwudebe
**Matric:** 2026/A/MIT/0517
**Course:** MIT 8103 Advanced Database Systems
**Portfolio:** 4 - NoSQL and Advanced Data Models
**Case study:** CampusNest - Private Student Accommodation Booking

---

## TL;DR

CampusNest runs a **hybrid** data layer:

- **PostgreSQL** owns the booking / tenancy / rent core (Portfolios 1-3).
  That workload is highly relational, needs strict ACID transactions,
  needs exclusion constraints (no two tenancies on the same room at the
  same time), and the rent instalments must sum to no more than the
  annual rent - enforced by `CHECK` constraints.
- **MongoDB** owns the maintenance-ticket workload (Portfolio 4). Each
  ticket has a polymorphic schema that differs per category (plumbing,
  electrical, furniture, pest_control), accumulates arrays of photos and
  status_history, and is read by a "show me this ticket with everything
  attached" path that benefits from a single document fetch instead of a
  five-table JOIN.

This split is not a fad. It is the natural seam in the data: where the
data is highly relational and consistency is non-negotiable, SQL wins;
where the data is hierarchical, polymorphic, and read-heavy on a
"fetch-the-whole-thing" path, NoSQL wins.

---

## When SQL wins

**1. Strict, up-front schema with cross-row constraints.** The
`tenancy` table in Portfolio 1 has an exclusion constraint
`EXCLUDE USING gist (room_id WITH =, daterange(start_date, end_date) WITH &&)`
that forbids overlapping tenancies on the same room. That constraint is
a property of *two rows taken together*, not of a single row. No
document-store validator can express that, because a document validator
only ever sees one document at a time.

**2. Multi-table joins with projection.** The Portfolio 2 queries join
`lodge`, `room_type`, `room`, `tenancy`, `tenant`, and `rent_instalment`
in a single SELECT. PostgreSQL's planner chooses hash joins, merge
joins, or nested loops based on table statistics. MongoDB has no join
planner: `$lookup` exists but is a left-outer join executed inside an
aggregation pipeline and is dramatically slower than a planned SQL join
on indexed foreign keys.

**3. ACID transactions across multiple rows.** The `reserve_room()`
function in Portfolio 3 updates `room`, inserts into `tenancy`, inserts
into `rent_instalment`, and inserts into `reservation_log` inside one
`BEGIN ... COMMIT` block. If any step fails, the whole transaction
rolls back. PostgreSQL gives you this for free. MongoDB only gained
multi-document ACID transactions in 4.0 (2018) and they are slower than
PostgreSQL's because of the distributed consensus MongoDB runs on every
shard - they exist, but they are not the default mental model.

**4. Aggregations that respect SQL semantics.** `SUM(rent_instalment.amount)
<= room_type.annual_rent` is a `CHECK` constraint enforced at insert and
update time. Aggregations like "outstanding rent per lodge per month"
are one SQL query. In MongoDB you would have to model the constraint in
application code or run it as a post-hoc aggregation that does not
prevent the bad write.

**5. Strong, configurable isolation.** PostgreSQL gives you READ
COMMITTED, REPEATABLE READ, and SERIALIZABLE; Portfolio 3 uses
`SELECT ... FOR UPDATE SKIP LOCKED` for the waitlist and demonstrates a
deadlock. MongoDB's isolation story is "snapshot reads on each document"
plus causal consistency - weaker and less tuneable.

---

## When NoSQL wins

**1. Polymorphic schema per row.** A plumbing ticket has
`affected_fixture`, `leak_present`, `water_shut_off_needed`; an
electrical ticket has `affected_appliance`, `voltage_issue`,
`spark_or_smoke`, `safety_hazard`; a furniture ticket has `item_type`,
`damage_type`, `requires_replacement`; a pest_control ticket has
`pest_type`, `infestation_level`, `treatment_method`. In SQL you must
either (a) put ~15 NULL columns on one `maintenance_ticket` table, (b)
split into four child tables and `UNION ALL` every dashboard query, or
(c) use EAV and lose typing. In MongoDB the per-category fields are
simply attached to the document, the `$jsonSchema` validator enforces
the common envelope, and `additionalProperties:true` leaves room for the
per-category extras. This is the canonical case for a document store.

**2. Embedded arrays that are always read with their parent.** Every
time the maintenance dashboard opens a ticket, it wants the photos, the
status_history, and the technician_visits. In SQL that is a 5-table
JOIN (`maintenance_ticket` + `ticket_photo` + `status_history` +
`technician_visit` + optional `technician`). In MongoDB it is a single
`findOne({ticket_id: ...})` that returns one document with three
embedded arrays. Fewer round trips, no join planner to mis-estimate,
and the natural shape of the data on the wire is exactly what the
front-end renders.

**3. Read-heavy "show me the whole thing" workload.** A lodge manager
opens a ticket 50 times a day to read its history; the ticket itself is
written maybe 5 times in its lifetime. The read:write ratio is heavily
skewed toward reads, and the reads want the whole aggregate. That is
the textbook case for embedding instead of normalising.

**4. Horizontal scale.** MongoDB shards by a shard key and the driver
routes queries to the right shard. For a maintenance-ticket collection
that grows by ~50,000 tickets per academic session across four lodges,
sharding by `lodge_id` keeps every lodge's tickets on one shard and
lets the cluster grow by adding shards. PostgreSQL can partition by
range (Portfolio 5 does monthly partitioning) but cross-shard
distributed queries are not PostgreSQL's sweet spot.

**5. Schema evolution without ALTER TABLE migrations.** Adding a new
per-category field (say `warranty_claim_ref` to plumbing tickets) is a
no-op in MongoDB - the next write simply attaches the field. In SQL it
is an `ALTER TABLE` that locks the table on most engines.

---

## For CampusNest: the hybrid architecture

```
+-------------------+        +-------------------+
|   PostgreSQL      |        |     MongoDB       |
|   campusnest db   |        | campusnest_nosql  |
|-------------------|        |-------------------|
| lodge             |        | maintenance_      |
| room_type         |        |   tickets         |
| room              |        |   (polymorphic,   |
| tenant            |        |    embedded       |
| tenancy           |        |    photos +       |
| rent_instalment   |        |    history +      |
| waitlist          |        |    visits)        |
| reservation_log   |        |                   |
+-------------------+        +-------------------+
        |                            |
        |  tenancy.room_id  <----->  lodge_id, room_code
        |  (denormalised reference carried on each ticket)
        v                            v
   Portfolios 1-3              Portfolio 4
   (design, optimisation,      (NoSQL, schema validator,
    transactions)               aggregations, indexes)
```

Each maintenance ticket carries `lodge_id`, `lodge_name`, and
`room_code` as denormalised copies of the SQL-side primary keys. The
SQL side stays authoritative for lodges, rooms, tenants, tenancies, and
rent. The MongoDB side stays authoritative for the maintenance history
of those rooms. The denormalisation is small (three fields) and
read-only from the MongoDB side, which is the case where
denormalisation is cheap.

---

## Trade-offs

| Aspect | PostgreSQL | MongoDB (for the maintenance-ticket use case) |
|--------|------------|-----------------------------------------------|
| Schema | Fixed, declared up front, enforced per-row and across rows (CHECK, FK, EXCLUDE). | Flexible; `$jsonSchema` validates the common envelope, `additionalProperties:true` leaves room for per-category fields. |
| Transactions | Native multi-row ACID, four isolation levels, `SELECT ... FOR UPDATE`. | Multi-document ACID since 4.0, but slower because of distributed consensus; single-document atomicity is the default model. |
| Joins | Planned, costed, optimised; hash / merge / nested-loop. | No planner; `$lookup` is a left-outer join inside an aggregation pipeline. Embedding avoids the join for the common case. |
| Consistency model | Strong by default; serialisable available. | Strong per document; causal consistency optional across sessions; tunable read/write concern. |
| Scaling model | Vertical primarily; horizontal via partitioning and logical replication (Portfolio 5). | Horizontal via sharding; shard key decides data distribution. |
| Schema evolution | `ALTER TABLE` - cost varies by engine. | Add a field on the next write - no migration needed. |
| Polymorphic rows | Painful: NULLs, or child tables + UNION, or EAV. | Natural: per-document fields. |
| Best fit at CampusNest | Booking / tenancy / rent core. | Maintenance tickets. |

---

## Conclusion

The maintenance-ticket workload is the textbook case for MongoDB:
polymorphic schema per category, embedded arrays of photos and history,
read-heavy single-document fetch. The booking / tenancy / rent workload
is the textbook case for PostgreSQL: strict schema, cross-row
constraints, multi-row ACID transactions, multi-table joins. By
splitting CampusNest across the two stores and joining them through a
small denormalised reference (lodge_id + room_code carried on each
ticket), the portfolio gets the best of both worlds - and demonstrates,
concretely, why "use the right tool for each workload" is a stronger
engineering position than "use one database for everything".
