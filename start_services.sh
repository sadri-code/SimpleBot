#!/bin/bash
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting services..."

# 1. Start SSH
mkdir -p /var/run/sshd
/usr/sbin/sshd

# 2. Start Bot in background
if [ -d "/bot" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting bot..."
    cd /bot
    screen -dmS bot npm start
fi

# 3. Start Automator in background on port 3000
if [ -d "/automator" ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting automator on internal port 3000..."
    cd /automator
    export PORT=3000
    # Use tsx to run the TypeScript server file directly
    screen -dmS automator npx tsx server.ts
fi

sleep 10

# Remove default nginx startup to run in foreground
nginx -g "daemon off;"
