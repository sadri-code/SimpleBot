const express = require('express');
const http = require('http');
const path = require('path');
const { createProxyMiddleware } = require('http-proxy-middleware');
const setupSSHWebSocket = require('./ssh-server');

const app = express();
const server = http.createServer(app);
const PORT = process.env.PORT || 10000;

// Automator internal address
const AUTOMATOR_URL = 'http://localhost:3000';

// Setup SSH WebSocket
setupSSHWebSocket(server);

// Serve the terminal HTML page
app.get('/ssh', (req, res) => {
    res.sendFile(path.join(__dirname, 'terminal.html'));
});

// Health check endpoints
app.get('/health', (req, res) => res.send('OK'));

// Proxy all other requests to the automator (must be after specific routes)
app.use('/', createProxyMiddleware({ target: AUTOMATOR_URL, changeOrigin: true, ws: true }));

// Start server
server.listen(PORT, '0.0.0.0', () => {
    console.log(`🌐 Web server listening on port ${PORT}`);
    console.log(`🔌 SSH terminal available at /ssh`);
    console.log(`🤖 Automator available at root (/)`);
});
