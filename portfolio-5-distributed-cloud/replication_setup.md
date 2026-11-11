# Portfolio 5 - Streaming read replica: what `replication_demo.sh` does and why

**Student:** Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
**Case study:** CampusNest - Private Student Accommodation Booking

CampusNest's room-search pages are read-heavy, especially during the rent
rush at the start of a session. They can be served from a **read replica**,
while bookings, rent payments and maintenance tickets are written to the
**primary**. `replication_demo.sh` builds that pair inside one Codespace and
proves it works. `run_p5.sh` runs it and saves `replication_output.log`.

```bash
bash replication_demo.sh                   # build, test, then stop the replica
KEEP_REPLICA=1 bash replication_demo.sh    # build, test, leave it running on 5433
```

## The steps

| # | Step | Why it is done this way in Codespaces |
|---|---|---|
| 1 | Check `wal_level`, `max_wal_senders`, `hot_standby` on the primary | PostgreSQL 16's defaults (`replica`, 10, on) already allow streaming replication, so the primary does not need a restart. The script only changes `wal_level` if it finds `minimal`. |
| 2 | `pg_basebackup -h /var/run/postgresql -U postgres -D /var/lib/postgresql/16/replica -R -X stream -c fast` | Runs as the `postgres` OS user over the Unix socket. Ubuntu's default `local replication all peer` line allows it, so no password and no `pg_hba.conf` edit are needed. `-R` writes `standby.signal` and `primary_conninfo`. |
| 3 | Write a small `postgresql.conf` (port 5433, `hot_standby = on`), copy `pg_hba.conf` and `pg_ident.conf` into the replica directory, `chmod 700` | Ubuntu keeps config files in `/etc/postgresql/16/main`, not in the data directory, so a base backup has none. Without them the replica will not start. |
| 4 | `/usr/lib/postgresql/16/bin/pg_ctl -D ... -l replica.log -w start` | Codespaces has no systemd, and `pg_ctl` is not on the PATH. |
| 5 | `pg_is_in_recovery()` and `current_setting('port')` on 5432 and 5433 | Shows which server is the primary and which is the replica. `inet_server_port()` would be NULL over a socket. |
| 6 | `INSERT` on 5433 | It is rejected: `cannot execute INSERT in a read-only transaction`. |
| 7 | Insert a maintenance ticket on 5432, then read it on 5433 | The new row appears on the replica within a second, and the tenancy counts match on both servers. |
| 8 | `pg_stat_replication` on the primary; `pg_last_wal_replay_lsn()` and `now() - pg_last_xact_replay_timestamp()` on the replica | Shows the replica is `streaming`, the link is `async`, and how far behind it is (bytes and time). Primary-only functions are only called on the primary. |
| 9 | Delete the test ticket on the primary, then stop the replica | The delete replicates too. Stopping the replica saves Codespace memory. |

## Async vs sync

The demo uses **asynchronous** replication: the primary does not wait for
the replica before confirming a commit. A booking is never slowed down by
the replica, but if the primary failed, the last fraction of a second of
changes might not have reached the replica yet. With
`synchronous_standby_names` set, the primary waits for the replica, so no
committed booking can be lost, but every commit gets slower. The trade-off
for CampusNest is discussed in `cloud_architecture.md` (CAP section).

## Evidence

All the real output is in `replication_output.log` (and in `p5_output.log`).
