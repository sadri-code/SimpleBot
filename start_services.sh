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

# ==================== CLONE / UPDATE AUTOMATOR REPOSITORY ====================
if [ -n "$GITHUB_TOKEN" ]; then
    log "Setting up automator repository..."
    if [ -d "/automator/.git" ]; then
        log "Updating existing automator repository..."
        cd /automator
        git pull
    else
        log "Cloning automator repository..."
        # Note: repo must be accessible with the provided GITHUB_TOKEN
        git clone https://$GITHUB_TOKEN@github.com/sdrelay/automator.git /automator
        cd /automator
    fi
    # Install dependencies
    npm install
    cd /
    log "Automator repository ready."
else
    log "GITHUB_TOKEN not set, skipping automator setup."
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

# ==================== RUN AUTOMATOR (Node.js web app) ====================
if [ -d "/automator" ]; then
    log "Starting automator web app..."
    cd /automator
    # Try to use npm start; fallback to node server.js if no start script
    if npm run | grep -q start; then
        npm start &
    else
        node server.js &
    fi
    AUTOMATOR_PID=$!
    cd /
    log "Automator started with PID $AUTOMATOR_PID"
else
    log "Automator directory not found, skipping."
fi

log "All services started. Container will now wait for background processes."

# ==================== WAIT FOR ANY PROCESS TO EXIT ====================
# Wait for any background job to finish. The screen session runs independently,
# so the container stays alive as long as at least one background process (SSH, web, etc.) is running.
wait -n

# If we reach here, a service has exited. Render will restart the container.
exit $?
