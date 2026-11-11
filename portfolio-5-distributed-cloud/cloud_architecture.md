# Portfolio 5 - Cloud Architecture for CampusNest

**Student:** Amaka Benedicta Chukwudebe
**Matric:** 2026/A/MIT/0517
**Course:** MIT 8103 Advanced Database Systems (Miva Open University)
**Case:** CampusNest - Private Student Accommodation Booking
**Study sessions covered:** Session 2 (Distributed DB), Session 3 (Cloud DB), Session 6 (Data Security and Privacy - NDPA 2023)

---

## A. Architecture diagram

CampusNest serves students near UNILAG (Akoka), YABATECH (Yaba), LASU (Ojo),
and UNN (Nsukka). The vast majority of users are physically in Nigeria, so
the entire data plane - primary, replica, backups, object storage, and the
MongoDB replica set - is hosted in Nigeria. Two rules drive this (Section B):
the NDPA 2023 only allows personal data to leave Nigeria when the destination
gives adequate protection or another lawful basis applies, and the Central
Bank of Nigeria's June 2026 circular requires payment transaction data
generated in Nigeria to be stored and managed in Nigeria from 1 January 2027.
CampusNest's rent payments go through a licensed Nigerian payment provider,
and keeping the instalment records here too keeps both sides consistent.

For the diagram, the chosen home region is a Lagos-based data centre
(for example MDXi or Rack Centre in Lagos). A cloud region outside Nigeria,
such as AWS `af-south-1` (Cape Town), is NOT used for the live data: it would
need an NDPA transfer assessment and could not hold payment data after
1 January 2027. A CDN edge in Lagos (for example Cloudflare's Lagos point of
presence) serves static assets and room-search pages so they reach
students in Akoka, Yaba, Ojo, and Nsukka in under ~30 ms.

```
                           Nigerian students (UNILAG, YABATECH, LASU, UNN)
                                          |
                                          v
                          +-------------------------------------------------+
                          |  CDN edge in Lagos (CloudFront / Cloudflare)    |
                          |  caches static room-search HTML + room photos    |
                          +-------------------------------------------------+
                                          |
                                          v
                          +-------------------------------------------------+
                          |  Application tier (Lagos DC)                     |
                          |  Next.js API: room-search (READ)  +  booking     |
                          |  (WRITE) + waitlist + maintenance tickets        |
                          +-------------------------------------------------+
                           |                              |             |
            READ (room     | WRITE (bookings,             | photos     |
            search)        |  rent, tenancy)              | (S3 PUT)   |
            v              v                              v             v
   +-----------------+  +-----------------+   +-----------------+   +---------+
   | Read replica    |  | Primary PG 16   |   | MongoDB replica |   | S3-comp |
   | campusnest_ro   |  | campusnest      |   | set (3 nodes)   |   | object  |
   | port 5433       |  | port 5432       |   | maintenance_db  |   | storage |
   | (streaming WAL  |<-| (writes only)   |   | tickets +       |   | ticket  |
   |  from primary)  |  | PgBouncer pool  |   | photo metadata  |   | photos  |
   +-----------------+  +-----------------+   +-----------------+   +---------+
          |                      |                     |                  |
          |                      |                     |                  |
          +----------+-----------+---------+-----------+----------+------+
                     |                     |                      |
                     v                     v                      v
          +---------------------+ +-------------------+ +-------------------+
          | nightly pg_baseback | | WAL archive to    | | MongoDB oplog     |
          | -> second AZ in NG  | | S3 in NG (WAL     | | backup to second  |
          | (PITR retained 30d) | | gzipped, 30d)     | | AZ in NG          |
          +---------------------+ +-------------------+ +-------------------+

   Legend: NG = Nigeria. All arrows above stay inside Nigeria.
   The only outbound path is the CDN edge fetching static assets from the
   origin in the Lagos DC; no student PII crosses the Nigerian border.
```

The PostgreSQL primary + streaming read replica shown above is exactly the
topology built in `replication_setup.md` (primary on port 5432, replica on
port 5433). PgBouncer sits in front of the primary in transaction-mode
pooling so the rush (Section E) does not exhaust the primary's
`max_connections`. The MongoDB replica set hosts maintenance tickets (the
NoSQL workload from Portfolio 4) with one primary and two secondaries, all
in the same Nigerian DC across different racks/AZs. Ticket photos are
written to S3-compatible object storage (e.g. MinIO or AWS S3 in a
Nigerian region) and only their object URL + metadata are stored in
MongoDB.

---

## B. NDPA 2023 (Nigeria Data Protection Act 2023) compliance

The NDPA 2023 is the primary Nigerian data-protection statute (signed into
law on 13 June 2023, replacing the 2017 Nigeria Data Protection Regulation
- NDPR). It is administered by the Nigeria Data Protection Commission
(NDPC). CampusNest processes personal data of tenants and guarantors
(names, phone numbers, addresses, next-of-kin, payment histories,
maintenance ticket photos that may contain faces) - so CampusNest is a
"data controller" under the NDPA and must comply.

### What the NDPA 2023 requires (the obligations most relevant to CampusNest)

1. **Lawful basis for processing** (Sections 24, 25, 27) - processing must
   rest on consent, contract, legal obligation, vital interest, public
   task, or legitimate interest. CampusNest's bookings rest on **contract**;
   marketing rests on **consent** that the data subject can withdraw.
2. **Data minimisation** (Section 34) - collect only what is necessary.
   CampusNest does not need a tenant's BVN or NIN for a room booking; we
   collect name, phone, email, course, and guarantor contact only.
3. **Storage limitation** (Section 34) - keep data only as long as needed.
   Tenancy rows are retained 7 years after the tenancy ends (for tax /
   dispute purposes under FIRS rules), then anonymised.
4. **Security safeguards** (Sections 28, 29, 39) - technical and
   organisational measures appropriate to the risk: encryption, access
   control, logging.
5. **Breach notification within 72 hours** (Section 40) - notify the NDPC
   and the affected data subjects within 72 hours of becoming aware of a
   personal-data breach, with the nature, scope, and remedial steps.
6. **Data subject rights** (Sections 32, 33) - access, rectification,
   erasure ("right to be forgotten"), data portability, and objection.

### How the architecture keeps data inside Nigeria

Every store in the diagram in Section A sits in a Nigerian region (Lagos
DC; no live data in a foreign region, see Section A). The
primary PostgreSQL, the read replica, the MongoDB replica set, the S3-
compatible object storage, the nightly base backups, and the WAL archive
all live on Nigerian soil. Cross-border transfer of personal data is
allowed under the NDPA only where the destination gives adequate protection
or another lawful basis applies (Part VIII, sections 41-43), and payment
transaction data must stay in Nigeria under the CBN's localisation rule from
1 January 2027 - so CampusNest's default is **no cross-border transfer**.

### Specific technical controls baked into the design

| NDPA principle | Technical control |
|----------------|-------------------|
| Security safeguard | **Encryption at rest**: PostgreSQL TDE via `pgcrypto` for PII columns (tenant.phone, guarantor.phone), LUKS full-disk encryption on the data volume, MongoDB encryption at rest, S3 server-side encryption (SSE-S3 / SSE-KMS). |
| Security safeguard | **Encryption in transit**: TLS 1.2+ (prefer 1.3) on every connection - app-to-primary, primary-to-replica (the `primary_conninfo` in Step 6 of `replication_setup.md` uses `sslmode=require` in production), app-to-MongoDB, app-to-S3, CDN-to-origin. |
| Security safeguard | **Row-level security** (RLS) on `tenant`, `guarantor`, `tenancy`, `rent_instalment` so a lodge manager connected as role `lodge_mgr_<lodge_id>` can only SELECT rows for their own lodge - enforced server-side, not in app code. |
| Security safeguard | **Audit logging**: `pgaudit` extension on the primary logs every DML and DDL; MongoDB profiler logs reads/writes on sensitive collections; S3 access logs. Logs shipped to a write-once bucket. |
| Security safeguard | **Least-privilege roles**: `app_write` (INSERT/UPDATE only on booking tables), `app_read` (SELECT only), `lodge_mgr_<id>` (per-lodge RLS), `finance` (SELECT on rent_instalment + maintenance aggregates). No shared superuser in production - unlike the `db_admin` role used in this portfolio for development. |
| Breach notification (72h) | **Breach playbook**: SIEM alerting on `pgaudit` anomalies (mass SELECT on `tenant`, login from new IP, replication-slot drop) triggers a runbook that notifies the NDPC within 72h if a confirmed breach. |
| Data subject rights | **Access / rectification**: a `data_subject_request` table records each request, with a 30-day SLA enforced by a daily cron job. **Erasure**: a `forget_tenant(p_tenant_id)` procedure pseudonymises PII columns (sets name/phone/email to NULL or hash) but keeps the tenancy + rent rows for the 7-year tax retention; the NDPA allows retention for legal obligation. |
| Storage limitation | **Partitioning by month** (this portfolio's `partition.sql`) lets us `DETACH PARTITION rent_instalment_2026_09` and archive it to cold storage after retention expires - the partition boundary is the natural retention boundary. |

---

## C. CAP theorem analysis

The CAP theorem (Study Session 2) says a distributed system can guarantee
at most two of {Consistency, Availability, Partition tolerance} during a
network partition. Since partitions CAN happen, the real choice is C vs A
when the network splits.

### Primary + streaming read replica (the PostgreSQL side)

CampusNest's replication is **asynchronous** (the default; see Section D
for the per-transaction override). Under a network partition that isolates
the replica from the primary:

- The **primary keeps accepting writes** - it does NOT block. So write
  availability is preserved.
- The **replica keeps serving reads** from the WAL it has already replayed.
  Those reads are **eventually consistent**: they may be a few seconds
  behind the primary (replication lag).
- If the PRIMARY fails during the partition, the replica cannot be
  promoted safely without risking data loss (it may not have the last few
  WAL records). This is the **CP** bias: we sacrifice the ability to
  promote a stale replica rather than risk lost writes.

So: **the PostgreSQL primary+replica is CP for writes** (the primary is the
single source of truth; a write either commits on the primary or fails -
no stale write accepted) and **eventually consistent (AP-ish) for reads**
off the replica.

### MongoDB replica set (maintenance tickets from Portfolio 4)

MongoDB offers **tunable consistency** via `readPreference`:

- `readPreference=primary` - reads go to the replica-set primary only.
  Strong consistency, but the primary is a bottleneck during the rush.
- `readPreference=secondary` - reads fan out to secondaries. Eventually
  consistent (a just-logged ticket may not appear on a secondary for a few
  ms), but reads scale with the number of secondaries.
- `readPreference=nearest` - reads go to the lowest-latency node.

### Why CampusNest chose CP for bookings, AP-ish for maintenance reads

- **Bookings (PostgreSQL writes): CP.** Losing a booking is a financial
  and reputational disaster - a student who paid and got no room is a
  social-media incident. So the booking write MUST hit the primary and
  MUST commit durably. We accept lower write availability (the primary is
  a single point of write) in exchange for never losing a confirmed
  booking.
- **Maintenance ticket reads (MongoDB): AP-ish.** A student checking
  whether their plumbing ticket is "in progress" can tolerate seeing a
  status that is 5 seconds stale. So `readPreference=secondary` fans read
  load across the three secondaries and keeps the MongoDB primary free for
  write traffic (new ticket logs, status updates from technicians).

---

## D. Sync vs async replication trade-offs

### Synchronous replication

Configuration: `synchronous_commit = on` (default) +
`synchronous_standby_names = 'FIRST 1 (campusnest_ro)'` on the primary.
The primary then waits for the named replica to flush the WAL before it
reports `COMMIT` to the client.

- **Pro:** zero data loss on primary failure (the replica has every
  committed WAL record).
- **Con:** every write blocks until the replica ACKs. Write latency =
  primary flush + replica flush + one network round trip. A slow or
  network-partitioned replica stalls the primary entirely.

### Asynchronous replication (default)

Configuration: `synchronous_commit = on` (default for durability) but NO
`synchronous_standby_names` - the primary flushes locally and returns
`COMMIT` immediately; the replica streams the WAL in the background.

- **Pro:** write latency = local flush only. Fast.
- **Con:** a primary crash can lose the last few WAL records the replica
  had not yet replayed (the "replication lag" window, typically
  sub-second to a few seconds).

### CampusNest's choice

- **Default: async** for the room-search replica (the topology in
  `replication_setup.md`). The replica is read-only and tolerates a few
  seconds of lag; making every write synchronous would needlessly slow
  booking inserts.
- **Opt-in sync per critical transaction**: a final rent-payment
  confirmation (the moment a tenancy becomes legally binding) switches to
  synchronous commit for that one transaction only, so a primary crash in
  the millisecond after payment confirmation cannot lose the payment
  record. The exact SQL:

```sql
BEGIN;
SET LOCAL synchronous_commit = on;     -- this tx waits for the replica
-- Optional: name the replica to wait on, if synchronous_standby_names
-- is configured on the primary.
UPDATE rent_instalment
   SET status = 'paid', paid_at = now()
 WHERE instalment_id = 123456 AND due_date = '2026-10-01';
INSERT INTO payment_event (instalment_id, event, at)
VALUES (123456, 'final_payment_confirmed', now());
COMMIT;
```

`SET LOCAL` scopes the change to the current transaction - the next
transaction in the same session reverts to the default (async). This is
the classic "dial up consistency for the critical moment, dial it back
down for the rest" pattern from Study Session 2.

---

## E. Handling the start-of-session rent rush

At the start of every academic session, new rooms open and a "rent rush"
hits the website: thousands of students near UNILAG, YABATECH, LASU, and
UNN simultaneously search for rooms and attempt bookings. The primary
takes the booking writes; the replica serves the reads. Without scaling
tactics the primary saturates and bookings time out, losing revenue and
frustrating students.

### Tactics (each tied back to a study session)

1. **Read-heavy room-search traffic goes to the replica.** The
   room-search endpoint sets `app_read` role and hits `campusnest_ro` on
   port 5433. The primary is left free for booking writes. This is the
   read/write splitting pattern from Study Session 2's distributed-DB
   architecture, and the cloud scaling pattern from Study Session 3.
2. **Connection pooling with PgBouncer.** PgBouncer in `transaction`
   mode sits in front of the primary (port 6432 -> 5432) with a small
   pool of server connections (e.g. 25) that multiplex thousands of
   short-lived client connections. Without pooling, each student's
   browser opens a backend connection and the primary's
   `max_connections` (default 100) is exhausted in seconds.
3. **`SELECT ... FOR UPDATE SKIP LOCKED`** (introduced in Portfolio 3)
   for concurrent reservations on the same room type: two students
   racing for the last single-room do not block each other - one wins,
   the other is immediately routed to the waitlist. Without `SKIP LOCKED`
   the second student's transaction blocks until the first commits,
   serialising the rush.
4. **Pre-warm the room-search cache with a materialised view.** A
   `free_rooms_per_lodge_per_session` materialised view, refreshed every
   minute by an `REFRESH MATERIALIZED VIEW CONCURRENTLY` cron job running
   AGAINST THE REPLICA, is what the room-search page actually reads. The
   replica absorbs the read load; the primary is never touched by
   room-search. Caching is Study Session 3's cloud pattern.
5. **Waitlist as a pressure valve.** When a room type is sold out, the
   booking endpoint returns a 409 with a "join waitlist" link instead of
   retrying. The `waitlist_entry` INSERT (a cheap append) replaces a
   failed booking retry storm. The waitlist is drained when a current
   tenant cancels or when the lodge opens a new room type.
6. **Autoscale read replicas before the rush.** A second replica is
   cloned from the primary with `pg_basebackup` (same procedure as
   `replication_setup.md`, but port 5434) BEFORE the session opens.
   Reads fan out across both replicas through PgBouncer's `rw_split`
   routing. After the rush, the extra replica is stopped with `pg_ctl
   stop` to save cost.
7. **Rate limiting on the booking endpoint.** A simple token-bucket per
   tenant (10 booking attempts / minute) in the app tier prevents one
   student from holding a room by repeatedly reserving and releasing it.
   Rate limiting is also a Study Session 6 security control - it mitigates
   credential-stuffing and abuse alongside its rush-mitigation role.

### Expected rush-day behaviour with these tactics

- Room-search reads: served from the materialised view on the replica(s),
  p95 latency well under 100 ms even at 5,000 concurrent users.
- Booking writes: the primary sees ~50 writes/sec at peak (one booking
  per lodge per few seconds), each guarded by `SKIP LOCKED` - well within
  PgBouncer's 25-connection pool.
- Replication lag: stays under 2 seconds because the replica only
  replays the booking writes (low volume), not the read traffic.
- Waitlist growth: spikes for the first 48 hours of the rush, then
  drains as cancellations and new room openings flow through.

---

## F. Sharding vs partitioning note

CampusNest in this portfolio uses **partitioning** on a single PostgreSQL
node: `rent_instalment` is partitioned by `due_date` month (see
`partition.sql`). That is one node, one write head, and the partitions are
local table files - the goal is manageability (cheap archive of old
months, fast prune-by-date queries, smaller per-month VACUUMs) NOT
horizontal write scaling.

**Sharding** is different: the data is split across MULTIPLE PostgreSQL
nodes (e.g. shard `tenancy` by `lodge_id` so each lodge's tenancies live
on a different node). Sharding scales write throughput beyond what one
node can handle, but introduces distributed transactions, cross-shard
joins, and the CAP trade-offs from Section C in full force - exactly the
distributed-DB architecture of Study Session 2.

If CampusNest grew to hundreds of lodges and one PostgreSQL primary could
no longer absorb the booking-write rate, the next step would be to shard
`tenancy` and `rent_instalment` by `lodge_id` across, say, four PostgreSQL
shards, each with its own read replica. Bookings for UNILAG lodges would
hit shard 1, YABATECH lodges shard 2, LASU lodges shard 3, UNN lodges
shard 4. Cross-shard reports (finance across all lodges) would need a
federated query layer or an ETL into a cloud data warehouse (Study
Session 3's data-warehouse topic).

For the current scale of CampusNest (4 institutions, dozens of lodges,
~100k rent instalments): **partitioning + one read replica is enough.**
The sharding path is documented here as the explicit next step if the
business outgrows the single-primary design.

---

## Summary - how this document maps to the study sessions

| Section | Study session(s) | Topic |
|---------|-------------------|-------|
| A | Session 3 | Cloud database architecture, CDN, multi-tier app, object storage, backups |
| B | Session 6 + Session 3 | NDPA 2023, CBN payment-data localisation (Jan 2027), data residency, encryption at rest/in transit, RLS, audit logging, 72h breach notification, data subject rights |
| C | Session 2 | CAP theorem, consistency models, eventual consistency of async replica, MongoDB tunable read consistency |
| D | Session 2 | Sync vs async replication trade-off, per-transaction `SET LOCAL synchronous_commit` |
| E | Session 2 + Session 3 + Session 6 | Read/write splitting, PgBouncer pooling, `SKIP LOCKED`, materialised views, autoscaling, rate limiting |
| F | Session 2 | Sharding vs partitioning, when to move from one to many nodes |
