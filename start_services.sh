#!/bin/bash

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# ============================================
# Helper: restart a screen session
# ============================================
restart_screen() {
    local session_name=$1
    local workdir=$2
    local command=$3

    if screen -list | grep -q "\.${session_name}"; then
        log "Stopping existing screen session: $session_name"
        screen -S "$session_name" -X quit
        sleep 2
    fi

    cd "$workdir"
    screen -dmS "$session_name" $command
    log "Started screen session: $session_name -> $command"
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
                restart_screen "bot" "$REPO_BOT" "npm start"
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
                if [ -f "dist/server.js" ]; then
                    restart_screen "automator" "$REPO_AUTOMATOR" "bash -c 'node dist/server.js 2>&1 | tee -a /tmp/automator.log'"
                else
                    restart_screen "automator" "$REPO_AUTOMATOR" "bash -c 'npx tsx server.ts 2>&1 | tee -a /tmp/automator.log'"
                fi
            fi
        fi

        # ---- Health check ----
        if [ -d "$REPO_BOT" ] && ! screen -list | grep -q "\.bot"; then
            log "[Daemon] Bot screen missing, restarting"
            restart_screen "bot" "$REPO_BOT" "npm start"
        fi
        if [ -d "$REPO_AUTOMATOR" ] && ! screen -list | grep -q "\.automator"; then
            log "[Daemon] Automator screen missing, restarting"
            if [ -f "$REPO_AUTOMATOR/dist/server.js" ]; then
                restart_screen "automator" "$REPO_AUTOMATOR" "bash -c 'node dist/server.js 2>&1 | tee -a /tmp/automator.log'"
            else
                restart_screen "automator" "$REPO_AUTOMATOR" "bash -c 'npx tsx server.ts 2>&1 | tee -a /tmp/automator.log'"
            fi
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

# 4. Start automator (initial) with logging to file AND tee to stdout via a tail process
if [ -d "/automator" ]; then
    log "Starting automator on port 3000..."
    cd /automator
    export PORT=3000

    # Clear old log
    > /tmp/automator.log

    # Start the automator inside screen, output goes to log file
    if [ -f "dist/server.js" ]; then
        screen -dmS automator bash -c 'node dist/server.js 2>&1 | tee -a /tmp/automator.log'
    else
        screen -dmS automator bash -c 'npx tsx server.ts 2>&1 | tee -a /tmp/automator.log'
    fi

    # Give it a moment to start
    sleep 2

    # Start a background tail that prints automator logs to container stdout
    # This makes 'docker logs -f' show automator output in real time
    tail -f /tmp/automator.log &
    TAIL_PID=$!
    log "Automator log tail started (PID $TAIL_PID). Log file: /tmp/automator.log"

    if screen -list | grep -q "\.automator"; then
        log "Automator is running (screen session)"
    else
        log "ERROR: Automator failed to start. Check /tmp/automator.log"
    fi
fi

# 5. Nginx (foreground – keeps container alive)
sleep 5
log "Starting nginx..."
nginx -g "daemon off;"
