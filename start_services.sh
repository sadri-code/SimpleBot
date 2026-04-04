#!/bin/bash
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting services..."

# 1. Start SSH
mkdir -p /var/run/sshd
/usr/sbin/sshd

# 2. Start git-sync daemon in background
/git-sync.sh &

# 3. Start Bot in background
if [ -d "/bot" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting bot..."
    cd /bot
    screen -dmS bot npm start
fi

# 4. Start Automator with explicit error logging
if [ -d "/automator" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting automator on internal port 3000..."
    cd /automator
    export PORT=3000
    # Try using compiled output first; fallback to tsx if needed
    if [ -f "dist/server.js" ]; then
        screen -dmS automator node dist/server.js
    else
        screen -dmS automator bash -c 'export PORT=3000 && npx tsx server.ts 2>&1 | tee /tmp/automator.log'
    fi
fi

sleep 10

# Start nginx in foreground
nginx -g "daemon off;"
