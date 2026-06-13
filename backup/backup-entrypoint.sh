#!/bin/bash
# ──────────────────────────────────────────────
# OpenMRS DB Backup Container Entrypoint
# ──────────────────────────────────────────────

set -euo pipefail

echo "=========================================="
echo "  OpenMRS MariaDB Backup Service"
echo "=========================================="
echo ""
echo "  Host:          ${MYSQL_HOST:-db}"
echo "  Database:      ${MYSQL_DATABASE:-openmrs}"
echo "  Schedule:      ${BACKUP_SCHEDULE:-0 2 * * *}"
echo "  Local Retention: ${BACKUP_RETENTION_DAYS:-14} days"
echo "  Output Dir:    ${BACKUP_DIR:-/backups}"
echo "  Google Drive:  ${GDRIVE_ENABLED:-false}"
if [ "${GDRIVE_ENABLED:-false}" = "true" ]; then
  echo "  Drive Folder:  ${GDRIVE_FOLDER:-openmrs-backups}"
  echo "  GDrive Retention: ${GDRIVE_RETENTION_DAYS:-30} days"
fi
echo ""

# ── Verify connectivity to the database before starting ──
echo "Verifying connectivity to database..."
timeout 10 bash -c "until mysql -h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASSWORD -e 'SELECT 1' >/dev/null 2>&1; do echo 'Waiting for db...'; sleep 2; done"
echo "Database is reachable."

echo ""
echo "Starting backup service..."
exec /usr/local/bin/backup.sh
