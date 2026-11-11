# Notes on Third Normal Form (3NF) - CampusNest Portfolio 1

**Student:** Amaka Benedicta Chukwudebe
**Matric:** 2026/A/MIT/0517
**Course:** MIT 8103 Advanced Database Systems
**Study session:** 1 - Review of Traditional Relational Databases and Advanced Concepts

---

## 1. What 1NF, 2NF, and 3NF mean in plain English

Normalisation is the process of organising columns and tables to reduce data
redundancy and improve data integrity. The three forms used in this portfolio
build on each other: a table in 3NF is automatically in 2NF and 1NF.

**First Normal Form (1NF)** - "atomic values, no repeating groups."
A table is in 1NF when every column holds a single, indivisible value for
every row, and there are no repeating columns or nested tables. In
CampusNest, every column in every table is a scalar (a single text, number,
date, or timestamp). For example, a tenant has exactly one `email` and one
`phone`; we never store a comma-separated list of phone numbers in a single
field. A separate `maintenance_ticket` row is created when a tenant reports
two issues, rather than packing both summaries into one cell.

**Second Normal Form (2NF)** - "no partial dependency on part of a composite
primary key." A table is in 2NF when it is in 1NF and every non-key column
depends on the **whole** primary key, not just part of it. This is only
relevant when the primary key is composite. In CampusNest every table uses a
single-column surrogate primary key (`lodge_id`, `room_type_id`, etc.), so
there is no partial-key dependency by construction. The composite keys that do
exist (`UNIQUE(lodge_id, room_code)` on `room`, `UNIQUE(room_type_id,
position)` on `waitlist_entry`) are uniqueness constraints, not the primary
key, so they cannot introduce a partial dependency on the PK.

**Third Normal Form (3NF)** - "no transitive dependency." A table is in 3NF
when it is in 2NF and every non-key column depends on **nothing but the
primary key** - that is, no non-key column depends on another non-key column.
Informally: "every non-key attribute must provide a fact about the key, the
whole key, and nothing but the key." If column B depends on column A and
column A depends on the PK, then B depends on the PK *through* A - that is a
transitive dependency and a 3NF violation. The remedy is to split B out into
its own table keyed by A.

---

## 2. Per-table 3NF analysis

For each table, the primary key is the single `*_id` surrogate column. The
analysis confirms that every other column depends on that key directly, with
no partial or transitive dependency.

### 2.1 lodge  (PK: `lodge_id`)

| Column            | Depends on    | Why no violation                          |
|-------------------|---------------|-------------------------------------------|
| name              | lodge_id      | The lodge's name is a fact about the lodge. |
| nearest_school    | lodge_id      | Which school the lodge is near.           |
| address_line      | lodge_id      | Street address of the lodge.              |
| city              | lodge_id      | City the lodge sits in.                    |
| state             | lodge_id      | Nigerian state the lodge is in.           |
| created_at        | lodge_id      | Audit timestamp for the lodge row.        |

`city` and `state` are both facts about the lodge's location, not about each
other: a lodge in "Nsukka" is in "Enugu", but the row stores both because we
query them independently. There is no `city_id` that `state` would depend on
transitively.

### 2.2 room_type  (PK: `room_type_id`)

| Column            | Depends on     | Why no violation                          |
|-------------------|----------------|-------------------------------------------|
| lodge_id          | room_type_id   | Which lodge offers this room type (FK).   |
| name              | room_type_id   | single / shared_2 / shared_4.             |
| annual_rent_ngn   | room_type_id   | The rent for this room type at this lodge.|
| capacity          | room_type_id   | How many beds fit in this room type.      |

The rent is a fact about the room type at a given lodge; it does not depend
on the lodge alone (two lodges can have different rents for the same `name`).
So `annual_rent_ngn` depends on the full `room_type_id`, not on `lodge_id` or
`name` alone.

### 2.3 room  (PK: `room_id`)

| Column            | Depends on  | Why no violation                          |
|-------------------|-------------|-------------------------------------------|
| lodge_id          | room_id     | Which lodge the room is physically in.    |
| room_type_id      | room_id     | Which room type this room belongs to.     |
| room_code         | room_id     | Human-readable code (e.g. AH-S-101).      |
| floor             | room_id     | Which floor the room is on.               |
| created_at        | room_id     | Audit timestamp.                          |

`lodge_id` is technically derivable from `room_type_id` (a room type belongs
to one lodge), so keeping `lodge_id` on `room` is a small redundancy. It is
kept to avoid a join for common queries (find all rooms in lodge X). This is
a deliberate, minor denormalisation noted in section 3.

### 2.4 tenant  (PK: `tenant_id`)

| Column            | Depends on  | Why no violation                          |
|-------------------|-------------|-------------------------------------------|
| full_name         | tenant_id   | The tenant's name.                        |
| email             | tenant_id   | Unique contact email.                     |
| phone             | tenant_id   | Contact phone.                            |
| student_matric    | tenant_id   | University matriculation number.          |
| nearest_school    | tenant_id   | Which school the tenant studies at.       |
| created_at        | tenant_id   | Audit timestamp.                          |

`nearest_school` is stored on the tenant, not derived from the tenancy's
room, because a tenant's school is a fact about the student, not about a
specific booking.

### 2.5 guarantor  (PK: `guarantor_id`)

| Column            | Depends on    | Why no violation                          |
|-------------------|---------------|-------------------------------------------|
| tenant_id         | guarantor_id  | Which tenant this guarantor backs (FK).   |
| full_name         | guarantor_id  | Guarantor's name.                         |
| phone             | guarantor_id  | Guarantor's phone.                        |
| email             | guarantor_id  | Guarantor's email.                        |
| relationship      | guarantor_id  | Parent / Uncle / Aunt etc.                |
| home_address      | guarantor_id  | Guarantor's home address.                 |
| created_at        | guarantor_id  | Audit timestamp.                          |

No transitive dependencies: `relationship` does not determine `phone` or
`address`. Each column is an independent fact about the guarantor.

### 2.6 tenancy  (PK: `tenancy_id`)

| Column            | Depends on   | Why no violation                          |
|-------------------|--------------|-------------------------------------------|
| room_id           | tenancy_id   | Which room is let.                        |
| tenant_id         | tenancy_id   | Who holds the tenancy.                    |
| start_date        | tenancy_id   | When the tenancy starts.                  |
| end_date          | tenancy_id   | When the tenancy ends.                    |
| annual_rent_ngn   | tenancy_id   | Snapshot of rent at booking time.         |
| status            | tenancy_id   | active / ended / cancelled.               |
| created_at        | tenancy_id   | Audit timestamp.                          |

`annual_rent_ngn` here is a **deliberate snapshot** of
`room_type.annual_rent_ngn` at the moment the tenancy was signed (see section
3). Without the snapshot, changing the room type's rent retroactively would
rewrite history.

### 2.7 rent_instalment  (PK: `instalment_id`)

| Column            | Depends on      | Why no violation                          |
|-------------------|-----------------|-------------------------------------------|
| tenancy_id        | instalment_id   | Which tenancy this instalment pays toward.|
| due_date          | instalment_id   | When the instalment is due.               |
| amount_ngn        | instalment_id   | How much is due (Naira).                  |
| paid_at           | instalment_id   | When it was actually paid (nullable).     |
| status            | instalment_id   | pending / paid / overdue.                 |
| created_at        | instalment_id   | Audit timestamp.                          |

`status` is not derived from `paid_at` by a trigger - it is set explicitly
when the instalment is recorded as paid, so there is no transitive dependency.

### 2.8 waitlist_entry  (PK: `waitlist_id`)

| Column            | Depends on     | Why no violation                          |
|-------------------|----------------|-------------------------------------------|
| room_type_id      | waitlist_id    | Which room type is being queued for.      |
| tenant_id         | waitlist_id    | Which tenant is queuing.                  |
| position          | waitlist_id    | The tenant's place in the queue.          |
| joined_at         | waitlist_id    | When the tenant joined the waitlist.      |

`position` is unique per `room_type_id`, but it depends on the waitlist entry
(the act of queuing), not on the room type alone.

### 2.9 maintenance_ticket  (PK: `ticket_id`)

| Column            | Depends on  | Why no violation                          |
|-------------------|-------------|-------------------------------------------|
| lodge_id          | ticket_id   | Which lodge the ticket was raised at.     |
| room_id           | ticket_id   | Which room (nullable - common-area tickets).|
| tenant_id         | ticket_id   | Who reported it (nullable).               |
| category          | ticket_id   | plumbing / electrical / ...               |
| reported_at       | ticket_id   | When it was reported.                     |
| resolved_at       | ticket_id   | When it was resolved (nullable).          |
| status            | ticket_id   | open / in_progress / resolved / closed.   |
| summary           | ticket_id   | Free-text description of the issue.       |

`resolved_at` does not determine `status` (a ticket can be `closed` without a
resolve timestamp in the stub), so there is no transitive dependency.

---

## 3. Deliberate denormalisation (not 3NF violations)

Two intentional design choices store data that could theoretically be derived
elsewhere. Both are justified business decisions, not normalisation errors.

1. **`tenancy.annual_rent_ngn` is a historical snapshot.** The room type's
   rent can change from year to year (inflation, renovation). A tenancy
   signed in 2026 at NGN 850,000 must still read NGN 850,000 in 2029 even if
   the room type's current rent has risen to NGN 950,000. Storing the rent on
   the tenancy at booking time preserves the legal record. Without the
   snapshot, every rent report would have to time-travel through a rent
   history table, which is far more complex than a single snapshot column.
   This is the standard "slowly changing dimension" pattern, not a 3NF
   violation: the column depends on `tenancy_id` (which tenancy was signed)
   and on the booking date, both of which are part of the row's identity.

2. **`room.lodge_id` repeats what `room_type.lodge_id` already gives.** A
   room belongs to a room type, which belongs to a lodge, so `room.lodge_id`
   is derivable via `room_type`. We keep it on `room` to avoid a join for the
   very common query "list all rooms in lodge X" and because a room's
   physical lodge does not change even if its room type is reclassified. The
   redundancy is bounded (one extra column, never updated independently) and
   protected by the foreign key and the fact that both columns always point
   to the same lodge in the seed and bulk data.

All other tables are in strict 3NF: every non-key column depends on the key,
the whole key, and nothing but the key.
