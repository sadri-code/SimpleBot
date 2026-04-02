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
    
    # Show what files exist (debug)
    log "Contents of /automator:"
    ls -la
    log "Contents of /automator/dist (if exists):"
    ls -la dist 2>/dev/null || echo "dist directory not found"
    
    # Try to run the compiled output, or fallback to tsx
    if [ -f "dist/server.js" ]; then
        log "Running node dist/server.js"
        exec node dist/server.js
    elif [ -f "dist/index.js" ]; then
        log "Running node dist/index.js"
        exec node dist/index.js
    else
        log "No compiled output found, running with tsx"
        exec npx tsx server.ts
    fi
else
    log "ERROR: /automator directory not found. Exiting."
    exit 1
fi
