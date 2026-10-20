const http = require('http');
const express = require('express');
const cors = require('cors');
const { Server } = require('socket.io');

const path = require('path');
const fs = require('fs');

const db = require('./db');
const waManager = require('./whatsapp');
const { checkOllamaStatus, generateAiReply, resolveSystemPrompt, DEFAULT_SYSTEM_PROMPT } = require('./ai');

const app = express();
const PORT = process.env.PORT || 3001;

// Allowed origin validator for Localhost and LAN (Private IP) access
function isAllowedOrigin(origin) {
  if (!origin) return true; // Same-origin or server-to-server
  try {
    const url = new URL(origin);
    const host = url.hostname;
    return (
      host === 'localhost' ||
      host === '127.0.0.1' ||
      host.startsWith('192.168.') ||
      host.startsWith('10.') ||
      /^172\.(1[6-9]|2\d|3[0-1])\./.test(host)
    );
  } catch (e) {
    return false;
  }
}

// Middlewares
app.use(cors({
  origin: (origin, callback) => {
    if (isAllowedOrigin(origin)) {
      callback(null, true);
    } else {
      callback(new Error('Origin tidak diizinkan oleh CORS'));
    }
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE'],
  credentials: true
}));

app.use(express.json());

// Serve static client build if available (e.g. Android portable single-port mode)
const clientDistPath = path.join(__dirname, '../client/dist');
if (fs.existsSync(clientDistPath)) {
  app.use(express.static(clientDistPath));
}

// HTTP Server & Socket.IO
const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: (origin, callback) => {
      callback(null, isAllowedOrigin(origin));
    },
    methods: ['GET', 'POST']
  }
});

// Attach Socket.IO to WhatsApp manager
waManager.setSocketIO(io);

// Socket.IO connection event
io.on('connection', (socket) => {
  // Send current status immediately upon client connection
  socket.emit('status_change', {
    status: waManager.getStatus().status,
    user: waManager.getStatus().user,
    qr: waManager.getQR().qr
  });

  socket.emit('auto_reply_status', {
    enabled: waManager.getAutoReplyEnabled()
  });
});

// ==========================================
// WHATSAPP API ROUTES
// ==========================================

// 1. GET /api/status -> { status, user }
app.get('/api/status', (req, res) => {
  const current = waManager.getStatus();
  res.json({
    status: current.status,
    user: current.user
  });
});

// 2. GET /api/qr -> { status, qr }
app.get('/api/qr', (req, res) => {
  const qrData = waManager.getQR();
  res.json({
    status: qrData.status,
    qr: qrData.qr
  });
});

// 3. GET /api/chats -> { success, chats }
app.get('/api/chats', (req, res) => {
  try {
    const chats = db.getChats();
    res.json({
      success: true,
      chats: chats || []
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      chats: [],
      error: err.message
    });
  }
});

// 4. GET /api/messages?chatId=xxx -> { success, chatId, messages }
app.get('/api/messages', (req, res) => {
  try {
    const chatId = req.query.chatId;
    if (!chatId) {
      return res.status(400).json({
        success: false,
        chatId: '',
        messages: [],
        error: 'Parameter chatId diperlukan.'
      });
    }

    // Reset unread count when reading messages
    db.resetChatUnread(chatId);
    const updatedChat = db.getChatById(chatId);
    if (updatedChat) {
      io.emit('chat_updated', updatedChat);
    }

    const messages = db.getMessages(chatId, 200);
    res.json({
      success: true,
      chatId,
      messages: messages || []
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      chatId: req.query.chatId || '',
      messages: [],
      error: err.message
    });
  }
});

// 5. POST /api/send-message -> { success, jid, message }, body { to, message }
app.post('/api/send-message', async (req, res) => {
  try {
    const { to, message } = req.body;
    if (!to || !message) {
      return res.status(400).json({
        success: false,
        error: 'Nomor tujuan (to) dan isi pesan (message) wajib diisi.'
      });
    }

    const result = await waManager.sendMessage(to, message);
    res.json({
      success: true,
      jid: result.jid,
      message: result.message
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// 6. POST /api/reset-session -> { success, status }
app.post('/api/reset-session', async (req, res) => {
  try {
    const result = await waManager.resetSession();
    res.json({
      success: true,
      status: result.status
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// ==========================================
// AI & SETTINGS ROUTES
// ==========================================

// 7. GET /api/ai/status -> { available, models, activeModel, message }
app.get('/api/ai/status', async (req, res) => {
  try {
    const status = await checkOllamaStatus();
    res.json(status);
  } catch (err) {
    res.status(500).json({
      available: false,
      error: err.message
    });
  }
});

// 8. POST /api/ai-reply -> body { message, systemPrompt? }
app.post('/api/ai-reply', async (req, res) => {
  try {
    const { message, systemPrompt } = req.body;
    if (!message) {
      return res.status(400).json({
        success: false,
        error: 'Field message diperlukan.'
      });
    }

    const aiResult = await generateAiReply({ message, systemPrompt });
    res.json({
      success: true,
      reply: aiResult.reply,
      model: aiResult.model,
      systemPrompt: aiResult.usedSystemPrompt
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// 9. GET /api/settings/system-prompt
app.get('/api/settings/system-prompt', (req, res) => {
  try {
    const saved = db.getSetting('ai_system_prompt');
    const effective = (saved && saved.trim().length > 0) ? saved.trim() : DEFAULT_SYSTEM_PROMPT;
    res.json({
      success: true,
      systemPrompt: effective
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      systemPrompt: DEFAULT_SYSTEM_PROMPT,
      error: err.message
    });
  }
});

// 10. POST /api/settings/system-prompt -> body { systemPrompt }
app.post('/api/settings/system-prompt', (req, res) => {
  try {
    const { systemPrompt } = req.body;
    if (typeof systemPrompt !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'systemPrompt harus berupa string.'
      });
    }

    db.setSetting('ai_system_prompt', systemPrompt);
    res.json({
      success: true,
      systemPrompt
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// ==========================================
// SI BONTOT AUTO-REPLY ROUTES
// ==========================================

// 11. GET /api/auto-reply/status
app.get('/api/auto-reply/status', async (req, res) => {
  try {
    const aiStatus = await checkOllamaStatus();
    res.json({
      success: true,
      enabled: waManager.getAutoReplyEnabled(),
      aiAvailable: aiStatus.available,
      activeModel: aiStatus.activeModel,
      processingCount: db.getActiveAutoReplyProcessingCount(),
      allowlist: waManager.getTestAllowlist()
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      enabled: waManager.getAutoReplyEnabled(),
      error: err.message
    });
  }
});

// 12. POST /api/auto-reply/settings -> body { enabled }
app.post('/api/auto-reply/settings', (req, res) => {
  try {
    const { enabled } = req.body;
    const updated = waManager.setAutoReplyEnabled(Boolean(enabled));
    res.json({
      success: true,
      enabled: updated
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// 13. GET /api/auto-reply/allowlist -> get active test isolation allowlist
app.get('/api/auto-reply/allowlist', (req, res) => {
  res.json({
    success: true,
    allowlist: waManager.getTestAllowlist()
  });
});

// 14. POST /api/auto-reply/allowlist -> body { allowlist: [...] }
app.post('/api/auto-reply/allowlist', (req, res) => {
  try {
    const { allowlist } = req.body;
    const updated = waManager.setTestAllowlist(allowlist);
    res.json({
      success: true,
      allowlist: updated
    });
  } catch (err) {
    res.status(500).json({
      success: false,
      error: err.message
    });
  }
});

// SPA Fallback for client routing (excluding API and Socket.IO routes)
if (fs.existsSync(clientDistPath)) {
  app.use((req, res, next) => {
    if (req.method !== 'GET' || req.path.startsWith('/api') || req.path.startsWith('/socket.io')) {
      return next();
    }
    res.sendFile(path.join(clientDistPath, 'index.html'));
  });
}

// Start server with EADDRINUSE handling
server.listen(PORT, () => {
  console.log(`[WA BONTOT Backend] Berjalan di http://localhost:${PORT}`);
  // Requirement: Default MUST be OFF after implementation and on server restart
  waManager.setAutoReplyEnabled(false);
  // Initialize WhatsApp connection
  waManager.init();
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`[ERROR] Port ${PORT} sudah digunakan oleh aplikasi lain!`);
    console.error(`Silakan tutup proses yang sedang memakai port ${PORT} atau jalankan dengan PORT berbeda (misal: PORT=3002).`);
    console.error(`Catatan: Jika Anda mengubah port backend atau environment variable, pastikan restart aplikasi dan sesuaikan VITE_API_BASE_URL di client/.env.local`);
    process.exit(1);
  } else {
    console.error('[ERROR Backend]', err);
  }
});
