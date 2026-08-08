#!/bin/bash

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Store PID and log inside the automator project folder
AUTOMATOR_PID_FILE="/automator/automator.pid"
AUTOMATOR_LOG="/automator/automator.log"

# ============================================
# Start automator (only if not already running)
# ============================================
start_automator() {
    cd /automator || return 1
    export PORT=3000

    # Check if already running
    if [ -f "$AUTOMATOR_PID_FILE" ]; then
        local old_pid=$(cat "$AUTOMATOR_PID_FILE")
        if kill -0 "$old_pid" 2>/dev/null; then
            log "Automator already running (PID $old_pid), not starting again."
            return 0
        else
            log "Stale PID file found, removing."
            rm -f "$AUTOMATOR_PID_FILE"
        fi
    fi

    # Clear previous log (only once, not on every restart)
    if [ ! -f "$AUTOMATOR_LOG" ]; then
        > "$AUTOMATOR_LOG"
    fi

    # Choose start command
            local cmd=""
            if [ -f "dist/index.js" ]; then
                cmd="node dist/index.js"
            elif [ -f "dist/server/index.js" ]; then
                cmd="node dist/server/index.js"
            elif [ -f "dist/server.js" ]; then
                cmd="node dist/server.js"
            elif [ -f "server/index.ts" ]; then
                cmd="npx tsx server/index.ts"
            else
                cmd="npx tsx server.ts"
            fi

    # Run automator with unbuffered output, redirect to log file
    (
        exec stdbuf -oL -eL bash -c "$cmd" >> "$AUTOMATOR_LOG" 2>&1
    ) &
    local new_pid=$!
    echo "$new_pid" > "$AUTOMATOR_PID_FILE"
    log "Automator started with PID $new_pid (log: $AUTOMATOR_LOG)"

    # Wait a moment to see if it dies
    sleep 3
    if ! kill -0 "$new_pid" 2>/dev/null; then
        log "ERROR: Automator exited immediately. Last log lines:"
        tail -20 "$AUTOMATOR_LOG"
    fi
}

# ============================================
# Restart bot screen session
# ============================================
restart_bot_screen() {
    if screen -list | grep -q "\.bot"; then
        screen -S bot -X quit
        sleep 2
    fi
    cd /bot || return
    screen -dmS bot npm start
    log "Bot screen restarted"
}

# ============================================
# Git sync daemon
# ============================================
git_sync_daemon() {
    local REPO_BOT="/bot"
    local REPO_AUTOMATOR="/automator"
    local CHECK_INTERVAL=60  # Check every 60 seconds (not 1s)

    log "[Daemon] Git sync started, checking every ${CHECK_INTERVAL}s"

    while true; do
        # Update bot
        if [ -d "$REPO_BOT" ]; then
            cd "$REPO_BOT" || continue
            git fetch origin 2>/dev/null || log "[Daemon] Bot: git fetch failed"
            LOCAL=$(git rev-parse HEAD 2>/dev/null)
            REMOTE=$(git rev-parse @{u} 2>/dev/null)
            if [ "$LOCAL" != "$REMOTE" ] && [ -n "$REMOTE" ]; then
                log "[Daemon] Updates detected for bot. Pulling..."
                git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || log "[Daemon] Bot: git pull failed"
                if [ -f package.json ]; then
                    MD5_BEFORE=$(md5sum package.json | cut -d' ' -f1)
                    npm install 2>&1 | tail -5
                    MD5_AFTER=$(md5sum package.json | cut -d' ' -f1)
                    [ "$MD5_BEFORE" != "$MD5_AFTER" ] && log "[Daemon] Bot: npm install completed"
                fi
                restart_bot_screen
            fi
        fi

        # Update automator
        if [ -d "$REPO_AUTOMATOR" ]; then
            cd "$REPO_AUTOMATOR" || continue
            git fetch origin 2>/dev/null || log "[Daemon] Automator: git fetch failed"
            LOCAL=$(git rev-parse HEAD 2>/dev/null)
            REMOTE=$(git rev-parse @{u} 2>/dev/null)
            if [ "$LOCAL" != "$REMOTE" ] && [ -n "$REMOTE" ]; then
                log "[Daemon] Updates detected for automator. Pulling..."
                git pull origin main 2>/dev/null || git pull origin master 2>/dev/null || log "[Daemon] Automator: git pull failed"
                if [ -f package.json ]; then
                    MD5_BEFORE=$(md5sum package.json | cut -d' ' -f1)
                    npm install 2>&1 | tail -5
                    MD5_AFTER=$(md5sum package.json | cut -d' ' -f1)
                    [ "$MD5_BEFORE" != "$MD5_AFTER" ] && log "[Daemon] Automator: npm install completed"
                fi
                if grep -q '"build"' package.json 2>/dev/null; then
                    log "[Daemon] Running npm run build"
                    npm run build 2>&1 | tail -10
                fi
                start_automator
            fi
        fi

        # Health check automator – only restart if PID file missing or process dead
        if [ ! -f "$AUTOMATOR_PID_FILE" ]; then
            log "[Daemon] No PID file, starting automator"
            start_automator
        else
            local pid=$(cat "$AUTOMATOR_PID_FILE" 2>/dev/null)
            if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
                log "[Daemon] Automator process died, restarting"
                start_automator
            fi
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

# 2. Start git sync daemon (background)
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