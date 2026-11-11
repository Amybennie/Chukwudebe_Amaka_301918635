#!/usr/bin/env bash
# =============================================================================
# replication_demo.sh - Portfolio 5: streaming read replica, in ONE script
# Student : Amaka Benedicta Chukwudebe (2026/A/MIT/0517)
# Case    : CampusNest - Private Student Accommodation Booking
# -----------------------------------------------------------------------------
# Builds a hot-standby READ REPLICA of the campusnest primary inside the same
# Codespace, then proves it works:
#   1. primary settings (wal_level, max_wal_senders)
#   2. pg_basebackup of the primary into /var/lib/postgresql/16/replica (-R)
#   3. Ubuntu keeps config in /etc, so the copy has no postgresql.conf /
#      pg_hba.conf / pg_ident.conf: write a small conf (port 5433), copy hba
#      and ident, chmod 700, start it with pg_ctl
#   4. who is who: pg_is_in_recovery() and port on each server
#   5. a WRITE on the replica is rejected (read-only)
#   6. a new maintenance ticket written on the PRIMARY appears on the REPLICA
#   7. replication lag and pg_stat_replication on the primary
# All connections use the Unix socket as the postgres OS user (peer login),
# so no passwords and no pg_hba edits are needed.
# Re-runnable: an old replica is stopped and rebuilt.
# =============================================================================
set -euo pipefail

PGBIN=/usr/lib/postgresql/16/bin
RDIR=/var/lib/postgresql/16/replica
SOCK=/var/run/postgresql
PRIMARY=(sudo runuser -u postgres -- psql -h "$SOCK" -p 5432 -d campusnest -v ON_ERROR_STOP=1)
REPLICA=(sudo runuser -u postgres -- psql -h "$SOCK" -p 5433 -d campusnest)

hr() { echo; echo "------------------------------------------------------------"; echo " $1"; echo "------------------------------------------------------------"; }

hr "1. Primary settings needed for streaming replication"
"${PRIMARY[@]}" -c "SELECT name, setting FROM pg_settings
                    WHERE name IN ('wal_level','max_wal_senders','hot_standby','port') ORDER BY name;"
WAL=$("${PRIMARY[@]}" -tAc "SHOW wal_level")
if [ "$WAL" = "minimal" ]; then
    echo "wal_level is minimal - switching to replica and restarting the primary"
    "${PRIMARY[@]}" -c "ALTER SYSTEM SET wal_level = 'replica';"
    sudo pg_ctlcluster 16 main restart
fi

hr "2. Base backup of the primary -> $RDIR"
if sudo test -f "$RDIR/postmaster.pid"; then
    echo "Stopping the replica from a previous run ..."
    sudo runuser -u postgres -- "$PGBIN/pg_ctl" -D "$RDIR" -m fast -w stop || true
fi
sudo rm -rf "$RDIR"
sudo runuser -u postgres -- "$PGBIN/pg_basebackup" -h "$SOCK" -p 5432 -U postgres \
     -D "$RDIR" -R -X stream -c fast -P
echo "standby.signal present: $(sudo test -f "$RDIR/standby.signal" && echo yes || echo no)"
echo "primary_conninfo written by -R:"
sudo grep primary_conninfo "$RDIR/postgresql.auto.conf"

hr "3. Replica config (Ubuntu keeps config in /etc, so the copy has none)"
sudo runuser -u postgres -- bash -c "cat > '$RDIR/postgresql.conf' <<EOF
# CampusNest read replica
port = 5433
unix_socket_directories = '$SOCK'
listen_addresses = ''
hot_standby = on
hba_file = '$RDIR/pg_hba.conf'
ident_file = '$RDIR/pg_ident.conf'
EOF"
sudo cp /etc/postgresql/16/main/pg_hba.conf /etc/postgresql/16/main/pg_ident.conf "$RDIR/"
sudo chown postgres:postgres "$RDIR/pg_hba.conf" "$RDIR/pg_ident.conf"
sudo chmod 700 "$RDIR"
sudo runuser -u postgres -- "$PGBIN/pg_ctl" -D "$RDIR" -l "$RDIR/replica.log" -w start
sleep 2

hr "4. Who is who"
for p in 5432 5433; do
    sudo runuser -u postgres -- psql -h "$SOCK" -p "$p" -d campusnest -tAc \
      "SELECT 'port ' || current_setting('port') || ' -> ' ||
              CASE WHEN pg_is_in_recovery() THEN 'REPLICA (read-only, in recovery)' ELSE 'PRIMARY (read-write)' END"
done

hr "5. A write on the REPLICA is rejected"
"${REPLICA[@]}" -c "INSERT INTO maintenance_ticket (lodge_id, category, summary)
                    VALUES (1, 'other', 'should fail on replica');" 2>&1 || true

hr "6. Write on the PRIMARY, read it on the REPLICA"
TAG="Replication check $(date '+%H:%M:%S')"
TID=$("${PRIMARY[@]}" -tAqc "INSERT INTO maintenance_ticket (lodge_id, category, summary)
                            SELECT lodge_id, 'other', '$TAG' FROM lodge ORDER BY lodge_id LIMIT 1
                            RETURNING ticket_id")
echo "PRIMARY: inserted ticket_id $TID ('$TAG')"
for i in $(seq 1 20); do
    FOUND=$("${REPLICA[@]}" -tAc "SELECT count(*) FROM maintenance_ticket WHERE ticket_id = $TID")
    [ "$FOUND" = "1" ] && break
    sleep 0.25
done
echo "REPLICA: rows with ticket_id $TID = $FOUND"
"${REPLICA[@]}" -c "SELECT ticket_id, summary, reported_at FROM maintenance_ticket WHERE ticket_id = $TID;"
echo "Counts on both servers:"
echo "  primary tenancy rows: $("${PRIMARY[@]}" -tAc 'SELECT count(*) FROM tenancy')"
echo "  replica tenancy rows: $("${REPLICA[@]}" -tAc 'SELECT count(*) FROM tenancy')"

hr "7. Replication status and lag"
"${PRIMARY[@]}" -x -c "SELECT application_name, state, sync_state, sent_lsn, replay_lsn,
                             pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_behind, replay_lag
                        FROM pg_stat_replication;"
"${REPLICA[@]}" -c "SELECT pg_last_wal_replay_lsn() AS replayed_up_to,
                           now() - pg_last_xact_replay_timestamp() AS time_since_last_replayed_change;"

"${PRIMARY[@]}" -q -c "DELETE FROM maintenance_ticket WHERE ticket_id = $TID;"
echo "(test ticket $TID removed on the primary - the delete replicates too)"

hr "Done"
if [ "${KEEP_REPLICA:-0}" = "1" ]; then
    echo "Replica left running on port 5433."
else
    sudo runuser -u postgres -- "$PGBIN/pg_ctl" -D "$RDIR" -m fast -w stop
    echo "Replica stopped to save Codespace memory (re-run this script to rebuild it)."
fi
