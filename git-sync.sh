#!/bin/bash

REPO_BOT="/bot"
REPO_AUTOMATOR="/automator"
CHECK_INTERVAL=30  # seconds

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to restart a screen session
restart_screen() {
    local session_name=$1
    local workdir=$2
    local command=$3

    # Kill existing session if it exists
    if screen -list | grep -q "\.${session_name}"; then
        log "Stopping existing screen session: $session_name"
        screen -S "$session_name" -X quit
        sleep 2
    fi

    # Start new session
    cd "$workdir"
    screen -dmS "$session_name" $command
    log "Started screen session: $session_name with command: $command"
}

update_repo() {
    local repo_path=$1
    local service_name=$2
    local screen_name=$3
    local start_command=$4

    cd "$repo_path" || return 1

    # Fetch latest changes
    git fetch origin

    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse @{u})

    if [ "$LOCAL" != "$REMOTE" ]; then
        log "Updates detected for $service_name. Pulling..."

        # Save package.json hash before pull
        if [ -f package.json ]; then
            MD5_BEFORE=$(md5sum package.json | cut -d' ' -f1)
        else
            MD5_BEFORE=""
        fi

        # Pull changes (adjust branch name as needed)
        git pull origin main || git pull origin master

        # If package.json changed, run npm install
        if [ -f package.json ]; then
            MD5_AFTER=$(md5sum package.json | cut -d' ' -f1)
            if [ "$MD5_BEFORE" != "$MD5_AFTER" ]; then
                log "package.json changed. Running npm install..."
                npm install
            fi
        fi

        # If there is a build script, run it (for automator)
        if [ -f package.json ] && grep -q '"build"' package.json; then
            log "Running npm run build..."
            npm run build
        fi

        # Restart the service using screen
        restart_screen "$screen_name" "$repo_path" "$start_command"
    fi
}

log "Git sync daemon started. Checking every ${CHECK_INTERVAL}s."

while true; do
    update_repo "$REPO_BOT" "Relay bot" "bot" "npm start"
    update_repo "$REPO_AUTOMATOR" "Automator" "automator" "npx tsx server.ts"
    sleep "$CHECK_INTERVAL"
done
