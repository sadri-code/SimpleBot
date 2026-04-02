#!/bin/bash
set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting services..."

# SSH daemon (background)
if [ -f /usr/sbin/sshd ]; then
    log "Starting SSH daemon..."
    /usr/sbin/sshd -D &
fi

# Bot inside screen (background)
log "Starting bot..."
screen -dmS bot bash -c '
    cd /bot
    while true; do
        echo "[$(date)] Starting bot..."
        npm start || node index.js
        sleep 5
    done
'

# Start Automator in foreground
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting automator on port ${PORT:-10000}..."
cd /automator
# Use tsx directly to be safe
npx tsx server.ts
