const express = require('express');
const http = require('http');
const path = require('path');
const { createProxyMiddleware } = require('http-proxy-middleware');
const setupSSHWebSocket = require('./ssh-server');

const app = express();
const server = http.createServer(app);
const PORT = process.env.PORT || 10000;

const AUTOMATOR_URL = 'http://localhost:3000';

app.use(express.json({ limit: '10mb' }));

// ==================== Gemini API Proxy ====================
app.get('/api/gemini/status', (req, res) => {
  res.json({ geminiKeySet: !!process.env.GEMINI_API_KEY });
});

app.post('/api/gemini', async (req, res) => {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return res.status(500).json({ error: 'GEMINI_API_KEY not configured' });
  try {
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

// ==================== SSH WebSocket ====================
setupSSHWebSocket(server);

// ==================== Static Routes ====================
app.get('/ssh', (req, res) => {
  res.sendFile(path.join(__dirname, 'terminal.html'));
});

app.get('/health', (req, res) => res.send('OK'));

// ==================== Catch‑all Proxy ====================
app.use('/', createProxyMiddleware({
  target: AUTOMATOR_URL,
  changeOrigin: true,
  ws: false,
}));

server.listen(PORT, '0.0.0.0', () => {
  console.log(`🌐 Web server listening on port ${PORT}`);
  console.log(`🔌 SSH terminal available at /ssh`);
  console.log(`🤖 Automator available at root (/)`);
  console.log(`🔐 Gemini proxy available at /api/gemini`);
});
