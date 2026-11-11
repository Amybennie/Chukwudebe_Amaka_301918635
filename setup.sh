#!/usr/bin/env bash
# =============================================================================
# setup.sh - Codespaces bootstrap for MIT 8103 Advanced Database Systems
# Student : Amaka Benedicta Chukwudebe
# Matric  : 2026/A/MIT/0517
# Course  : Master of Information Technology, Miva Open University
# Case    : CampusNest - Private Student Accommodation Booking
# =============================================================================
#
# What this script does
# ---------------------
#   1. Removes the broken yarn.list apt source (expired key breaks apt-get).
#   2. Installs PostgreSQL 16 (PGDG repo if the image does not have it) and
#      MongoDB 8.0 + mongosh, plus the Python drivers the portfolios use.
#   3. Starts both servers WITHOUT systemd (Codespaces has no systemd, so
#      `systemctl start` fails there): pg_ctlcluster for PostgreSQL and
#      `mongod --fork` for MongoDB.
#   4. Creates the campusnest database, the db_admin role, and a superuser
#      role named after your Linux user (peer login over the Unix socket,
#      used by the Python scripts - no passwords anywhere).
#   5. Loads btree_gist and pgcrypto.
#
# Codespaces conventions followed
# -------------------------------
#   * sudo works only as root, so commands that must run as the postgres
#     OS user use `sudo runuser -u postgres -- ...`, never `sudo -u postgres`.
#   * pg_ctl is at /usr/lib/postgresql/16/bin/pg_ctl (not on PATH).
#   * All connections use the Unix socket /var/run/postgresql (TCP needs a
#     password on Ubuntu).
#
# Re-runnable: yes. Already-installed packages and existing objects are kept.
# =============================================================================
set -euo pipefail

ME="$(whoami)"
echo "============================================================"
echo " CampusNest portfolio - Codespaces bootstrap"
echo " Student: Amaka Benedicta Chukwudebe (2026/A/MIT/0517)"
echo "============================================================"

# shellcheck disable=SC1091
. /etc/os-release
CODENAME="${VERSION_CODENAME:-jammy}"

# ---------------------------------------------------------------------------
# 0. Broken yarn source.
# ---------------------------------------------------------------------------
sudo rm -f /etc/apt/sources.list.d/yarn.list

# ---------------------------------------------------------------------------
# 1. PostgreSQL 16 (skip if already installed).
# ---------------------------------------------------------------------------
if [[ ! -x /usr/lib/postgresql/16/bin/postgres ]]; then
    echo "[1] Installing PostgreSQL 16"
    sudo apt-get update -y
    if ! apt-cache show postgresql-16 >/dev/null 2>&1; then
        echo "    postgresql-16 not in this image's repos - adding the PGDG repo"
        sudo apt-get install -y curl ca-certificates gnupg
        sudo install -d /usr/share/postgresql-common/pgdg
        sudo curl -fsSL -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
            https://www.postgresql.org/media/keys/ACCC4CF8.asc
        echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main" \
            | sudo tee /etc/apt/sources.list.d/pgdg.list >/dev/null
        sudo apt-get update -y
    fi
    sudo apt-get install -y postgresql-16 postgresql-contrib-16 || \
        sudo apt-get install -y postgresql-16
else
    echo "[1] PostgreSQL 16 already installed - skipping apt"
fi

# ---------------------------------------------------------------------------
# 2. MongoDB 8.0 + mongosh (skip if already installed).
# ---------------------------------------------------------------------------
if ! command -v mongod >/dev/null 2>&1 || ! command -v mongosh >/dev/null 2>&1; then
    echo "[2] Installing MongoDB 8.0 (community) + mongosh"
    sudo apt-get install -y curl gnupg ca-certificates
    MONGO_CODENAME="$CODENAME"
    case "$MONGO_CODENAME" in focal|jammy|noble) ;; *) MONGO_CODENAME=jammy ;; esac
    curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc \
        | sudo gpg -o /usr/share/keyrings/mongodb-server-8.0.gpg --dearmor --yes
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${MONGO_CODENAME}/mongodb-org/8.0 multiverse" \
        | sudo tee /etc/apt/sources.list.d/mongodb-org-8.0.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y mongodb-org
else
    echo "[2] MongoDB + mongosh already installed - skipping apt"
fi

# ---------------------------------------------------------------------------
# 3. Python drivers for the Python scripts (P1 generator, P3 race demos).
#    Codespaces' python3 is not the apt python, so install with pip.
# ---------------------------------------------------------------------------
echo "[3] Python drivers (psycopg2-binary, pymongo)"
python3 -m pip install --quiet psycopg2-binary pymongo 2>/dev/null \
  || python3 -m pip install --quiet --user psycopg2-binary pymongo 2>/dev/null \
  || python3 -m pip install --quiet --break-system-packages psycopg2-binary pymongo
python3 -c "import psycopg2, pymongo; print('    psycopg2', psycopg2.__version__, '| pymongo', pymongo.version)"

# ---------------------------------------------------------------------------
# 4. Start PostgreSQL (no systemd in Codespaces).
# ---------------------------------------------------------------------------
echo "[4] Starting PostgreSQL 16"
sudo pg_ctlcluster 16 main start 2>/dev/null || true
for _ in $(seq 1 20); do
    sudo runuser -u postgres -- pg_isready -q -h /var/run/postgresql && break
    sleep 1
done
sudo runuser -u postgres -- psql -tAc "SELECT version();"

# ---------------------------------------------------------------------------
# 5. Start MongoDB (no systemd in Codespaces).
# ---------------------------------------------------------------------------
echo "[5] Starting MongoDB"
if ! pgrep -x mongod >/dev/null; then
    sudo mkdir -p /var/lib/mongodb /var/log/mongodb
    if id mongodb >/dev/null 2>&1; then
        sudo chown -R mongodb:mongodb /var/lib/mongodb /var/log/mongodb
        sudo runuser -u mongodb -- mongod --config /etc/mongod.conf --fork >/dev/null
    else
        sudo mongod --dbpath /var/lib/mongodb --logpath /var/log/mongodb/mongod.log \
             --bind_ip 127.0.0.1 --fork >/dev/null
    fi
fi
for _ in $(seq 1 30); do
    mongosh --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1 && break
    sleep 1
done
echo "    mongod ping: $(mongosh --quiet --eval 'db.runCommand({ping:1}).ok')"

# ---------------------------------------------------------------------------
# 6. Roles + database (idempotent).
# ---------------------------------------------------------------------------
echo "[6] Creating roles and the campusnest database"
sudo runuser -u postgres -- psql -v ON_ERROR_STOP=1 -q <<SQL
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'db_admin') THEN
      CREATE ROLE db_admin WITH LOGIN SUPERUSER;
   END IF;
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${ME}') THEN
      CREATE ROLE "${ME}" WITH LOGIN SUPERUSER;
   END IF;
END\$\$;
SQL
if ! sudo runuser -u postgres -- psql -tAc "SELECT 1 FROM pg_database WHERE datname='campusnest'" | grep -q 1; then
    sudo runuser -u postgres -- psql -q -c "CREATE DATABASE campusnest OWNER db_admin ENCODING 'UTF8';"
fi
sudo runuser -u postgres -- psql -q -d campusnest -c "CREATE EXTENSION IF NOT EXISTS btree_gist;"
sudo runuser -u postgres -- psql -q -d campusnest -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"
sudo runuser -u postgres -- psql -d campusnest -c "\dx"
psql -h /var/run/postgresql -d campusnest -tAc "SELECT 'peer login as ' || current_user || ' works';"

cat <<EOF

============================================================
 SETUP COMPLETE
============================================================
 PostgreSQL 16 : socket /var/run/postgresql, database campusnest
                 psql as postgres : sudo runuser -u postgres -- psql -d campusnest
                 psql as you      : psql -h /var/run/postgresql -d campusnest
 MongoDB 8     : mongodb://127.0.0.1:27017   (shell: mongosh)

 After the Codespace sleeps, restart both with:
   sudo pg_ctlcluster 16 main start
   pgrep -x mongod || sudo runuser -u mongodb -- mongod --config /etc/mongod.conf --fork
============================================================
EOF
