#!/bin/bash
set -e

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Starting services..."

# ==================== OPTIONAL RUNTIME UPDATE ====================
# If you want to pull the latest bot code on every start, set GITHUB_TOKEN.
if [ -n "$GITHUB_TOKEN" ] && [ -d "/bot/.git" ]; then
    log "GITHUB_TOKEN detected, updating bot repository..."
    cd /bot
    git pull
    npm install
    cd /
    log "Bot repository updated."
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

# ==================== BOT INSIDE SCREEN (with auto‑restart) ====================
log "Starting bot inside a screen session (auto‑restart enabled)..."
# Create a detached screen session named "bot" that runs a restart loop
screen -dmS bot bash -c '
    cd /bot
    while true; do
        echo "[$(date)] Starting bot..."
        # Use npm start if defined, otherwise node index.js
        if npm run | grep -q start; then
            npm start
        else
            node index.js
        fi
        echo "[$(date)] Bot stopped. Restarting in 5 seconds..."
        sleep 5
    done
'
log "Bot screen session created. To attach: screen -r bot (via SSH)"

log "All services started. Container will now wait for background processes."

# ==================== WAIT FOR ANY PROCESS TO EXIT ====================
# Wait for any background job to finish. The screen session runs independently,
# so the container stays alive as long as at least one background process (SSH, web, etc.) is running.
wait -n

# If we reach here, a service has exited. Render will restart the container.
exit $?
