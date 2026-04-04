#!/bin/bash
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting services..."

# 1. Start SSH
mkdir -p /var/run/sshd
/usr/sbin/sshd

# 2. Start git-sync daemon in background (it will monitor and restart services as needed)
/git-sync.sh &

# 3. Start Bot in background (if not already started by git-sync, but we start it now)
if [ -d "/bot" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting bot..."
    cd /bot
    screen -dmS bot npm start
fi

# 4. Start Automator in background on port 3000
if [ -d "/automator" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting automator on internal port 3000..."
    cd /automator
    export PORT=3000
    screen -dmS automator npx tsx server.ts
fi

sleep 10

# Remove default nginx startup to run in foreground
nginx -g "daemon off;"
