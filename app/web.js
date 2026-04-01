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

// Enable JSON body parsing (needed for Gemini proxy)
app.use(express.json({ limit: '10mb' }));

// ==================== Automator API Endpoints ====================

// GET /api/status
app.get('/api/status', (req, res) => {
  // Return current status – you may need to fetch this from the bot
  res.json({
    status: {
      lastCheck: null,
      lastSuccess: null,
      remainingSeconds: 3600,
      isWorking: false,
      nextCheck: null,
      error: null
    },
    config: {
      cookieString: '',
      serverId: '',
      checkIntervalMin: 28,
      randomJitterMin: 2
    },
    logs: [], // empty array or real logs
    geminiKeySet: !!process.env.GEMINI_API_KEY
  });
});

// POST /api/config
app.post('/api/config', (req, res) => {
  const config = req.body;
  // Save config somewhere (file, memory, or pass to bot)
  console.log('Received config:', config);
  res.json({ success: true });
});

// GET /api/captcha/pending
app.get('/api/captcha/pending', (req, res) => {
  // Return any pending CAPTCHA if exists
  res.json(null); // or { id, image }
});

// POST /api/captcha/solve
app.post('/api/captcha/solve', (req, res) => {
  const { id, solution } = req.body;
  console.log(`CAPTCHA ${id} solved with: ${solution}`);
  res.json({ success: true });
});

// POST /api/logs/clear
app.post('/api/logs/clear', (req, res) => {
  // Clear logs
  res.json({ success: true });
});

// ==================== Gemini API Proxy ====================

app.get('/api/gemini/status', (req, res) => {
  res.json({ geminiKeySet: !!process.env.GEMINI_API_KEY });
});

// This endpoint forwards requests to Gemini, keeping the API key secret on the server.
// It must be placed BEFORE the catch-all proxy.
app.post('/api/gemini', async (req, res) => {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        return res.status(500).json({ error: 'GEMINI_API_KEY not configured' });
    }

    try {
        // Forward the request to Gemini API
        const response = await fetch('https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': apiKey,
            },
            body: JSON.stringify(req.body),
        });

        const data = await response.json();
        res.status(response.status).json(data);
    } catch (err) {
        console.error('Gemini proxy error:', err);
        res.status(500).json({ error: 'Failed to contact Gemini API' });
    }
});

// ==================== SSH WebSocket Setup ====================
// This attaches WebSocket upgrade handlers for the SSH terminal.
setupSSHWebSocket(server);

// ==================== Static Routes ====================
// Serve the terminal HTML page
app.get('/ssh', (req, res) => {
    res.sendFile(path.join(__dirname, 'terminal.html'));
});

// Health check endpoint
app.get('/health', (req, res) => res.send('OK'));

// ==================== Catch-all Proxy for Automator ====================
// Proxy all other HTTP requests to the automator on port 3000.
// ws: false is important – we want the SSH WebSocket to be handled by setupSSHWebSocket,
// not proxied to the automator. The automator likely doesn't need WebSocket proxying.
app.use('/', createProxyMiddleware({
    target: AUTOMATOR_URL,
    changeOrigin: true,
    ws: false,      // Disable WebSocket proxying to avoid conflict with SSH terminal
}));

// Start server
server.listen(PORT, '0.0.0.0', () => {
    console.log(`🌐 Web server listening on port ${PORT}`);
    console.log(`🔌 SSH terminal available at /ssh`);
    console.log(`🤖 Automator available at root (/)`);
    console.log(`🔐 Gemini proxy available at /api/gemini`);
});
