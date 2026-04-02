#!/bin/bash
set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting services..."

# ==================== SSH DAEMON ====================
if [ -f /usr/sbin/sshd ]; then
    log "Starting SSH daemon..."
    /usr/sbin/sshd -D &
    SSHD_PID=$!
    log "SSH daemon started with PID $SSHD_PID"
fi

# ==================== BOT INSIDE SCREEN ====================
log "Starting bot inside a screen session (auto‑restart enabled)..."
screen -dmS bot bash -c '
    cd /bot
    while true; do
        echo "[$(date)] Starting bot..."
        if npm run | grep -q start; then
            npm start
        else
            node index.js
        fi
        echo "[$(date)] Bot stopped. Restarting in 5 seconds..."
        sleep 5
    done
'
log "Bot screen session created."

# ==================== AUTOMATOR INSIDE SCREEN ====================
if [ -d "/automator" ]; then
    log "Starting automator inside a screen session on port 10000..."
    screen -dmS automator bash -c '
        cd /automator
        while true; do
            echo "[$(date)] Starting automator backend..."
            NODE_ENV=production PORT=10000 node dist/server.js   # or tsx? Use the built output
            echo "[$(date)] Automator stopped. Restarting in 5 seconds..."
            sleep 5
        done
    '
    log "Automator screen session created."
fi

log "All services started. Container will now wait for background processes."
wait -n
exit $?
