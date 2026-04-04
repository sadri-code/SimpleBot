#!/bin/bash

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# PID file for automator
AUTOMATOR_PID_FILE="/tmp/automator.pid"

# ============================================
# Start automator as background process
# ============================================
start_automator() {
    cd /automator || return 1
    export PORT=3000

    # Kill existing process if any
    if [ -f "$AUTOMATOR_PID_FILE" ]; then
        local old_pid=$(cat "$AUTOMATOR_PID_FILE")
        kill -0 "$old_pid" 2>/dev/null && kill "$old_pid" && sleep 2
    fi

    # Use stdbuf to disable buffering (ensures logs appear instantly)
    if [ -f "dist/server.js" ]; then
        stdbuf -oL -eL node dist/server.js &
    else
        stdbuf -oL -eL npx tsx server.ts &
    fi

    local new_pid=$!
    echo "$new_pid" > "$AUTOMATOR_PID_FILE"
    log "Automator started with PID $new_pid"
}

# ============================================
# Restart bot screen session (unchanged)
# ============================================
restart_bot_screen() {
    if screen -list | grep -q "\.bot"; then
        screen -S bot -X quit
        sleep 2
    fi
    cd /bot
    screen -dmS bot npm start
    log "Bot screen restarted"
}

# ============================================
# Git sync daemon (runs in background)
# ============================================
git_sync_daemon() {
    local REPO_BOT="/bot"
    local REPO_AUTOMATOR="/automator"
    local CHECK_INTERVAL=30

    log "[Daemon] Git sync started, checking every ${CHECK_INTERVAL}s"

    while true; do
        # ---- Update bot ----
        if [ -d "$REPO_BOT" ]; then
            cd "$REPO_BOT" || continue
            git fetch origin
            LOCAL=$(git rev-parse HEAD)
            REMOTE=$(git rev-parse @{u} 2>/dev/null)
            if [ "$LOCAL" != "$REMOTE" ] && [ -n "$REMOTE" ]; then
                log "[Daemon] Updates detected for bot. Pulling..."
                git pull origin main || git pull origin master
                if [ -f package.json ]; then
                    MD5_BEFORE=$(md5sum package.json | cut -d' ' -f1)
                    npm install
                    MD5_AFTER=$(md5sum package.json | cut -d' ' -f1)
                    [ "$MD5_BEFORE" != "$MD5_AFTER" ] && log "[Daemon] npm install completed"
                fi
                restart_bot_screen
            fi
        fi

        # ---- Update automator ----
        if [ -d "$REPO_AUTOMATOR" ]; then
            cd "$REPO_AUTOMATOR" || continue
            git fetch origin
            LOCAL=$(git rev-parse HEAD)
            REMOTE=$(git rev-parse @{u} 2>/dev/null)
            if [ "$LOCAL" != "$REMOTE" ] && [ -n "$REMOTE" ]; then
                log "[Daemon] Updates detected for automator. Pulling..."
                git pull origin main || git pull origin master
                if [ -f package.json ]; then
                    MD5_BEFORE=$(md5sum package.json | cut -d' ' -f1)
                    npm install
                    MD5_AFTER=$(md5sum package.json | cut -d' ' -f1)
                    [ "$MD5_BEFORE" != "$MD5_AFTER" ] && log "[Daemon] npm install completed"
                fi
                if grep -q '"build"' package.json 2>/dev/null; then
                    log "[Daemon] Running npm run build"
                    npm run build
                fi
                # Restart automator process
                start_automator
            fi
        fi

        # ---- Health check for automator (restart if dead) ----
        if [ -f "$AUTOMATOR_PID_FILE" ]; then
            local pid=$(cat "$AUTOMATOR_PID_FILE")
            if ! kill -0 "$pid" 2>/dev/null; then
                log "[Daemon] Automator process died, restarting"
                start_automator
            fi
        else
            start_automator
        fi

        # ---- Health check for bot screen ----
        if [ -d "$REPO_BOT" ] && ! screen -list | grep -q "\.bot"; then
            log "[Daemon] Bot screen missing, restarting"
            restart_bot_screen
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# ============================================
# MAIN startup sequence
# ============================================
log "Starting services..."

# 1. SSH
mkdir -p /var/run/sshd
/usr/sbin/sshd

# 2. Start git sync daemon in background
git_sync_daemon &

# 3. Start bot (initial)
if [ -d "/bot" ]; then
    log "Starting bot..."
    cd /bot
    screen -dmS bot npm start
fi

# 4. Start automator (initial) – logs go directly to stdout
if [ -d "/automator" ]; then
    log "Starting automator on port 3000..."
    start_automator
fi

# 5. Nginx (foreground – keeps container alive)
sleep 5
log "Starting nginx..."
nginx -g "daemon off;"
