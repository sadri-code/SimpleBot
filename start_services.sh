#!/bin/bash

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Store PID and log inside the automator project folder
AUTOMATOR_PID_FILE="/automator/automator.pid"
AUTOMATOR_LOG="/automator/automator.log"

# ============================================
# Start automator with logging (files in /automator/)
# ============================================
start_automator() {
    cd /automator || return 1
    export PORT=3000

    # Kill existing process using PID file
    if [ -f "$AUTOMATOR_PID_FILE" ]; then
        local old_pid=$(cat "$AUTOMATOR_PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log "Stopping old automator process (PID $old_pid)"
            kill "$old_pid"
            sleep 2
        fi
    fi

    # Clear previous log
    > "$AUTOMATOR_LOG"

    # Choose start command
    local cmd=""
    if [ -f "dist/server.js" ]; then
        cmd="node dist/server.js"
    else
        cmd="npx tsx server.ts"
    fi

    # Run automator with unbuffered output, tee to log file
    (
        exec stdbuf -oL -eL bash -c "$cmd 2>&1" | tee -a "$AUTOMATOR_LOG"
    ) &
    local new_pid=$!
    echo "$new_pid" > "$AUTOMATOR_PID_FILE"
    log "Automator started with PID $new_pid (PID file: $AUTOMATOR_PID_FILE, log: $AUTOMATOR_LOG)"

    # Check if it dies immediately
    sleep 3
    if ! kill -0 "$new_pid" 2>/dev/null; then
        log "ERROR: Automator exited immediately. Last log lines:"
        if [ -s "$AUTOMATOR_LOG" ]; then
            cat "$AUTOMATOR_LOG"
        else
            echo "(no output captured)"
        fi
    fi
}

# ============================================
# Restart bot screen session (no changes)
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
# Git sync daemon
# ============================================
git_sync_daemon() {
    local REPO_BOT="/bot"
    local REPO_AUTOMATOR="/automator"
    local CHECK_INTERVAL=30

    log "[Daemon] Git sync started, checking every ${CHECK_INTERVAL}s"

    while true; do
        # Update bot
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

        # Update automator
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
                start_automator
            fi
        fi

        # Health check automator
        if [ -f "$AUTOMATOR_PID_FILE" ]; then
            local pid=$(cat "$AUTOMATOR_PID_FILE")
            if ! kill -0 "$pid" 2>/dev/null; then
                log "[Daemon] Automator process died, restarting"
                start_automator
            fi
        else
            start_automator
        fi

        # Health check bot screen
        if [ -d "$REPO_BOT" ] && ! screen -list | grep -q "\.bot"; then
            log "[Daemon] Bot screen missing, restarting"
            restart_bot_screen
        fi

        sleep "$CHECK_INTERVAL"
    done
}

# ============================================
# MAIN
# ============================================
log "Starting services..."

# 1. SSH
mkdir -p /var/run/sshd
/usr/sbin/sshd

# 2. Start git sync daemon
git_sync_daemon &

# 3. Start bot (initial)
if [ -d "/bot" ]; then
    log "Starting bot..."
    cd /bot
    screen -dmS bot npm start
fi

# 4. Start automator (initial)
if [ -d "/automator" ]; then
    log "Starting automator on port 3000..."
    start_automator

    # Tail the automator log to show logs in console
    (
        sleep 2
        tail -F "$AUTOMATOR_LOG" 2>/dev/null
    ) &
    log "Log tail started for $AUTOMATOR_LOG"
fi

# 5. Nginx (foreground)
sleep 5
log "Starting nginx..."
nginx -g "daemon off;"
