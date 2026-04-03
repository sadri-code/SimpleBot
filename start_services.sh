#!/bin/bash
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting services..."

# 1. Start SSH
/usr/sbin/sshd

# 2. Start Bot in background
cd /bot
screen -dmS bot npm start

# 3. Start Automator in background on port 3000
cd /automator
export PORT=3000
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting automator on internal port 3000..."
screen -dmS automator npx tsx server.ts

# 4. Start Nginx in foreground on port 10000
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting Nginx dummy proxy on port 10000..."
# Remove default nginx startup to run in foreground
nginx -g "daemon off;"
