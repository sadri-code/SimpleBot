#!/bin/bash
set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting services..."

# ==================== OPTIONAL RUNTIME UPDATE ====================
if [ -n "$GITHUB_TOKEN" ] && [ -d "/bot/.git" ]; then
    log "GITHUB_TOKEN detected, updating bot repository..."
    cd /bot
    git pull
    npm install
    cd /
    log "Bot repository updated."
fi

# ==================== AUTOMATOR UPDATE ====================
if [ -n "$GITHUB_TOKEN" ] && [ -d "/automator/.git" ]; then
    log "GITHUB_TOKEN detected, updating automator repository..."
    cd /automator
    git pull
    npm install
    npm run build   # rebuild if source changed
    cd /
fi

# ==================== SSH DAEMON ====================
if [ -f /usr/sbin/sshd ]; then
    log "Starting SSH daemon..."
    /usr/sbin/sshd -D &
    SSHD_PID=$!
    log "SSH daemon started with PID $SSHD_PID"
fi

# ==================== WEB SERVER (SSH TERMINAL) ====================
log "Starting web server..."
cd /app
node web.js &
WEB_PID=$!
log "Web server started with PID $WEB_PID"

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

# ==================== SERVE AUTOMATOR STATIC FILES ====================
if [ -d "/automator/dist" ]; then
    log "Starting automator static file server on port 3000..."
    serve -s /automator/dist -l 3000 &
    AUTOMATOR_PID=$!
    log "Automator served with PID $AUTOMATOR_PID on port 3000"
else
    log "Automator dist folder not found; skipping automator."
fi

log "All services started. Container will now wait for background processes."

wait -n
exit $?
