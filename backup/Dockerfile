FROM mariadb:10.11.7

# Install cron + rclone for scheduled backups and Google Drive sync
RUN apt-get update && \
    apt-get install -y --no-install-recommends cron curl unzip && \
    RCLONE_VERSION="1.74.3" && \
    curl -sSL "https://downloads.rclone.org/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-amd64.zip" -o rclone.zip && \
    unzip -o rclone.zip "rclone-v${RCLONE_VERSION}-linux-amd64/rclone" -d /usr/local/bin/ && \
    rm -rf rclone.zip tmp_unzip_dir_for_rclone && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /tmp/*

# Copy backup scripts into the container
COPY backup/backup.sh /usr/local/bin/backup.sh
COPY backup/backup-entrypoint.sh /entrypoint.sh

RUN chmod +x /usr/local/bin/backup.sh \
    && chmod +x /entrypoint.sh

# Default environment variables (can be overridden in docker-compose)
ENV BACKUP_SCHEDULE="0 2 * * *"
ENV BACKUP_RETENTION_DAYS="14"
ENV BACKUP_DIR="/backups"
ENV GDRIVE_ENABLED="false"
ENV GDRIVE_FOLDER="openmrs-backups"
ENV GDRIVE_RETENTION_DAYS="30"
ENV GDRIVE_CREDENTIALS_PATH="/root/.config/rclone/credentials.json"

ENTRYPOINT ["/entrypoint.sh"]
