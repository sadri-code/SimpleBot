#!/bin/bash
set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting services..."

# ==================== SSH DAEMON (background) ====================
if [ -f /usr/sbin/sshd ]; then
    log "Starting SSH daemon in background..."
    /usr/sbin/sshd -D &
    SSHD_PID=$!
    log "SSH daemon started with PID $SSHD_PID"
fi

# ==================== BOT INSIDE SCREEN (background) ====================
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

# ==================== AUTOMATOR (FOREGROUND - for Render) ====================
if [ -d "/automator" ]; then
    log "Starting automator backend in foreground (using PORT=${PORT:-10000})..."
    cd /automator
    
    # Use the compiled output (your Dockerfile already runs npm run build)
    # Fallback to tsx if dist doesn't exist
    if [ -f "dist/server.js" ]; then
        exec node dist/server.js
    else
        exec npx tsx server.ts
    fi
else
    log "ERROR: /automator directory not found. Exiting."
    exit 1
fi
