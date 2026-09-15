#!/bin/bash

set -euo pipefail

DB_CONTAINER="db"          # container_name from docker-compose.yml
DB_NAME="${POSTGRES_DB:-appdb}"
DB_USER="${POSTGRES_USER:-appuser}"
BACKUP_DIR="/var/backups/db"
RETENTION_DAYS=7

TIMESTAMP="$(date '+%Y%m%d')"
DUMP_FILE="db_backup_${TIMESTAMP}.sql"
DUMP_PATH="${BACKUP_DIR}/${DUMP_FILE}"

mkdir -p "$BACKUP_DIR"

echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') Starting database backup..."

# ---- Dump the database from inside the running container ----
docker exec -t "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DB_NAME" > "$DUMP_PATH"

# ---- Compress the dump (produces db_backup_YYYYMMDD.sql.gz) 
gzip -f "$DUMP_PATH"

echo "[INFO] Backup created: ${DUMP_PATH}.gz"

# ---- Retention: delete backups older than RETENTION_DAYS 
find "$BACKUP_DIR" -name "db_backup_*.sql.gz" -mtime +"$RETENTION_DAYS" -print -exec rm -f {} \;

echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') Backup completed successfully."
