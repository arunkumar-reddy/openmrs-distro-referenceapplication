#!/bin/bash
set -euo pipefail

# ──────────────────────────────────────────────
# OpenMRS MariaDB Backup Script
# Usage: backup.sh [--immediate]
#
# --immediate : Run a single backup and exit (for startup/cron)
# (no flag)   : Set up cron and keep running indefinitely
# ──────────────────────────────────────────────

# ── Configuration ──
BACKUP_DIR="${BACKUP_DIR:-/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/openmrs_${TIMESTAMP}.sql.gz"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
GDRIVE_ENABLED="${GDRIVE_ENABLED:-false}"
GDRIVE_FOLDER="${GDRIVE_FOLDER:-OpenMRS Backups}"
GDRIVE_RETENTION_DAYS="${GDRIVE_RETENTION_DAYS:-30}"
GDRIVE_CREDENTIALS_PATH="${GDRIVE_CREDENTIALS_PATH:-/root/.config/rclone/credentials.json}"

# ── Create backup directory ──
mkdir -p "$BACKUP_DIR"

# ── Configure rclone for Google Drive ──
configure_rclone() {
  if [ "$GDRIVE_ENABLED" != "true" ]; then
    return
  fi

  mkdir -p /root/.config/rclone

  # Generate rclone config file
  cat > /root/.config/rclone/rclone.conf << EOF
[gdrive]
type = drive
EOF

  if [ -s "$GDRIVE_CREDENTIALS_PATH" ]; then
    echo "service_account_file = ${GDRIVE_CREDENTIALS_PATH}" >> /root/.config/rclone/rclone.conf
    chmod 600 "$GDRIVE_CREDENTIALS_PATH"
    echo "rclone configured with service account credentials."
  else
    echo "WARNING: No Google Drive credentials found at ${GDRIVE_CREDENTIALS_PATH} — Drive uploads will be skipped."
    GDRIVE_ENABLED=false
  fi
}

# ── Perform the mysqldump and compress ──
run_backup() {
  echo "[${TIMESTAMP}] Starting database backup..."

  mysqldump \
    -h"$MYSQL_HOST" \
    -u"$MYSQL_USER" \
    -p"$MYSQL_PASSWORD" \
    --single-transaction \
    --routines \
    --triggers \
    --databases "$MYSQL_DATABASE" \
    | gzip > "$BACKUP_FILE"

  local size
  size=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "[${TIMESTAMP}] Backup completed: ${BACKUP_FILE} (${size})"

  # Upload to Google Drive if enabled
  if [ "$GDRIVE_ENABLED" = "true" ]; then
    upload_to_gdrive
  fi
}

# ── Upload backup to Google Drive ──
upload_to_gdrive() {
  echo "[${TIMESTAMP}] Uploading to Google Drive (${GDRIVE_FOLDER}/)..."
  if rclone copy "$BACKUP_FILE" "gdrive:${GDRIVE_FOLDER}/" \
    --log-file=/var/log/rclone-upload.log \
    --log-level INFO \
    --transfers=1 \
    2>&1; then
    echo "[${TIMESTAMP}] Google Drive upload completed."
  else
    echo "[${TIMESTAMP}] WARNING: Google Drive upload failed. Local backup is safe and intact."
  fi
}

# ── Clean up old local backups ──
cleanup_old_backups() {
  echo "[${TIMESTAMP}] Cleaning up local backups older than ${RETENTION_DAYS} days..."
  find "$BACKUP_DIR" -name "openmrs_*.sql.gz" -mtime +"$RETENTION_DAYS" -delete
  echo "[${TIMESTAMP}] Local cleanup complete."

  # Clean up old Drive backups
  if [ "$GDRIVE_ENABLED" = "true" ]; then
    cleanup_gdrive
  fi
}

# ── Clean up old Google Drive backups ──
cleanup_gdrive() {
  echo "[${TIMESTAMP}] Cleaning up old Drive backups (older than ${GDRIVE_RETENTION_DAYS} days)..."
  if rclone delete "gdrive:${GDRIVE_FOLDER}/" \
    --include "openmrs_*.sql.gz" \
    --min-age "${GDRIVE_RETENTION_DAYS}d" \
    --log-file=/var/log/rclone-delete.log \
    2>&1; then
    echo "[${TIMESTAMP}] Google Drive cleanup complete."
  else
    echo "[${TIMESTAMP}] WARNING: Google Drive cleanup failed."
  fi
}

# ── Immediate mode: run once and exit ──
if [ "${1:-}" = "--immediate" ]; then
  configure_rclone
  run_backup
  cleanup_old_backups
  exit 0
fi

# ── Daemon mode: set up cron and run forever ──
CRON_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
BACKUP_CRONTAB="/etc/crontabs/root"

echo "$CRON_SCHEDULE /usr/local/bin/backup.sh --immediate >> /var/log/openmrs-backup.log 2>&1" > "$BACKUP_CRONTAB"

# Run the first backup immediately on startup
configure_rclone
run_backup
cleanup_old_backups

# Start cron in foreground so the container stays alive
echo "[${TIMESTAMP}] Cron schedule: ${CRON_SCHEDULE}"
echo "[${TIMESTAMP}] Next backup: ${CRON_SCHEDULE}"
crond -f &
wait
