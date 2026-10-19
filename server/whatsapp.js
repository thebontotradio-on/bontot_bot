const path = require('path');
const fs = require('fs');
const qrcode = require('qrcode');
const pino = require('pino');
const {
  makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  fetchLatestBaileysVersion,
  Browsers
} = require('@whiskeysockets/baileys');

const db = require('./db');
const {
  MessageDeduplicator,
  buildMessageDeduplicationKey,
  formatJidDisplay,
  isFallbackOrGenericName
} = require('./utils');
const { checkOllamaStatus, generateContextualReply } = require('./ai');

const authDir = path.join(__dirname, 'auth_session');
if (!fs.existsSync(authDir)) {
  fs.mkdirSync(authDir, { recursive: true });
}

// Logger with minimal noisy output
const logger = pino({ level: 'silent' });

class WhatsAppManager {
  constructor() {
    this.sock = null;
    this.status = 'closed'; // 'connecting' | 'qr' | 'connected' | 'closed'
    this.currentQrCode = null;
    this.currentRawQr = null;
    this.currentUser = null;
    this.reconnectTimeout = null;
    this.deduplicator = new MessageDeduplicator(2000);
    this.io = null;
    this.isExplicitLogout = false;
    this.isConnecting = false;

    // Requirement: Default MUST be OFF on server startup and restart
    this.autoReplyEnabled = false;

    // Controlled test isolation: optional allowlist of JIDs allowed for auto-reply
    this.testAllowlist = new Set();
  }

  setSocketIO(io) {
    this.io = io;
  }

  emitStatus() {
    if (this.io) {
      this.io.emit('status_change', {
        status: this.status,
        user: this.currentUser,
        qr: this.currentQrCode
      });
    }
  }

  getStatus() {
    return {
      status: this.status,
      user: this.currentUser
    };
  }

  getQR() {
    return {
      status: this.status,
      qr: this.currentQrCode,
      rawQr: this.currentRawQr
    };
  }

  getAutoReplyEnabled() {
    return this.autoReplyEnabled;
  }

  setAutoReplyEnabled(enabled) {
    this.autoReplyEnabled = Boolean(enabled);
    db.setSetting('auto_reply_enabled', this.autoReplyEnabled ? '1' : '0');
    if (this.io) {
      this.io.emit('auto_reply_status', {
        enabled: this.autoReplyEnabled
      });
    }
    return this.autoReplyEnabled;
  }

  setTestAllowlist(jids) {
    if (Array.isArray(jids)) {
      this.testAllowlist = new Set(
        jids.map(j => (typeof j === 'string' ? j.trim() : '')).filter(Boolean)
      );
    } else if (jids instanceof Set) {
      this.testAllowlist = new Set(jids);
    } else {
      this.testAllowlist = new Set();
    }
    return Array.from(this.testAllowlist);
  }

  getTestAllowlist() {
    return Array.from(this.testAllowlist);
  }

  matchesAllowlist(rawJid) {
    if (!this.testAllowlist || this.testAllowlist.size === 0) {
      return true;
    }
    if (this.testAllowlist.has(rawJid)) return true;

    // Normalize comparison: strip @domain and non-digits
    const rawClean = (rawJid || '').replace(/@.*$/, '').replace(/\D/g, '');
    for (const item of this.testAllowlist) {
      if (item === rawJid) return true;
      const itemClean = item.replace(/@.*$/, '').replace(/\D/g, '');
      if (rawClean && itemClean && rawClean === itemClean) {
        return true;
      }
    }
    return false;
  }

  clearReconnectTimer() {
    if (this.reconnectTimeout) {
      clearTimeout(this.reconnectTimeout);
      this.reconnectTimeout = null;
    }
  }

  cleanupSocket() {
    if (this.sock) {
      try {
        this.sock.ev.removeAllListeners();
        if (this.sock.ws) {
          this.sock.ws.close();
        }
      } catch (err) {
        // Silently continue cleanup
      }
      this.sock = null;
    }
  }

  /**
   * Resolve known contact name from contacts DB, existing chat, or Baileys LID mapping.
   */
  resolveContactName(jid, pushName = '') {
    if (!jid) return 'Unknown';

    // 1. If valid pushName provided, return it
    if (pushName && !isFallbackOrGenericName(pushName, jid)) {
      return pushName.trim();
    }

    // 2. Check contacts table
    const contact = db.getContact(jid);
    if (contact && contact.name && !isFallbackOrGenericName(contact.name, jid)) {
      return contact.name.trim();
    }

    // 3. Check existing chat table
    const chat = db.getChatById(jid);
    if (chat && chat.name && !isFallbackOrGenericName(chat.name, jid)) {
      return chat.name.trim();
    }

    // 4. If @lid, check Baileys reverse LID mapping in auth_session
    if (jid.endsWith('@lid')) {
      try {
        const lidNum = jid.split('@')[0];
        const reverseFile = path.join(authDir, `lid-mapping-${lidNum}_reverse.json`);
        if (fs.existsSync(reverseFile)) {
          const rawPhone = JSON.parse(fs.readFileSync(reverseFile, 'utf8'));
          if (rawPhone) {
            const mappedJid = `${rawPhone}@s.whatsapp.net`;
            const mappedContact = db.getContact(mappedJid);
            if (mappedContact && mappedContact.name && !isFallbackOrGenericName(mappedContact.name, mappedJid)) {
              return mappedContact.name.trim();
            }
            const mappedChat = db.getChatById(mappedJid);
            if (mappedChat && mappedChat.name && !isFallbackOrGenericName(mappedChat.name, mappedJid)) {
              return mappedChat.name.trim();
            }
          }
        }
      } catch (e) {
        // Silently continue to fallback
      }
    }

    // 5. Final fallback
    return formatJidDisplay(jid, pushName);
  }

  async init() {
    // Prevent simultaneous connection attempts
    if (this.isConnecting || (this.sock && this.status === 'connected')) {
      return;
    }

    this.isExplicitLogout = false;
    this.clearReconnectTimer();
    this.cleanupSocket();

    this.isConnecting = true;
    this.status = 'connecting';
    this.emitStatus();

    try {
      const { state, saveCreds } = await useMultiFileAuthState(authDir);
      const { version } = await fetchLatestBaileysVersion().catch(() => ({ version: [2, 3000, 1015901307] }));

      const sock = makeWASocket({
        version,
        auth: state,
        logger,
        printQRInTerminal: false,
        browser: Browsers.appropriate('Desktop') || ['Windows', 'Chrome', '10.0.0'],
        syncFullHistory: false,
        markOnlineOnConnect: false,
        defaultQueryTimeoutMs: 30000
      });

      this.sock = sock;

      // Handle credentials update
      sock.ev.on('creds.update', saveCreds);

      // Handle contacts updates from Baileys
      sock.ev.on('contacts.upsert', (contacts) => {
        if (!Array.isArray(contacts)) return;
        for (const c of contacts) {
          const name = c.name || c.verifiedName || c.notify;
          if (c.id && name && !isFallbackOrGenericName(name, c.id)) {
            db.saveContact(c.id, name);
          }
        }
      });

      sock.ev.on('contacts.update', (updates) => {
        if (!Array.isArray(updates)) return;
        for (const c of updates) {
          const name = c.name || c.verifiedName || c.notify;
          if (c.id && name && !isFallbackOrGenericName(name, c.id)) {
            db.saveContact(c.id, name);
          }
        }
      });

      // Handle connection update
      sock.ev.on('connection.update', async (update) => {
        // Ignore events if this socket is no longer the active one
        if (this.sock !== sock) return;

        const { connection, lastDisconnect, qr } = update;

        if (qr) {
          this.status = 'qr';
          this.currentRawQr = qr;
          try {
            this.currentQrCode = await qrcode.toDataURL(qr, {
              margin: 2,
              scale: 6,
              color: { dark: '#0b141a', light: '#ffffff' }
            });
          } catch (e) {
            this.currentQrCode = null;
          }
          this.emitStatus();
        }

        if (connection === 'open') {
          this.status = 'connected';
          this.currentQrCode = null;
          this.currentRawQr = null;
          this.isConnecting = false;

          const userJid = sock.user?.id || '';
          const userName = sock.user?.name || formatJidDisplay(userJid);
          this.currentUser = {
            id: userJid,
            name: userName
          };

          this.emitStatus();
        } else if (connection === 'close') {
          this.isConnecting = false;
          const statusCode = lastDisconnect?.error?.output?.statusCode;
          const isLoggedOut = statusCode === DisconnectReason.loggedOut;

          if (this.isExplicitLogout || isLoggedOut) {
            this.status = 'closed';
            this.currentUser = null;
            this.currentQrCode = null;
            this.emitStatus();
            this.clearSessionFiles();
          } else {
            // Reconnect safely with single timer
            this.status = 'connecting';
            this.emitStatus();
            this.clearReconnectTimer();
            this.reconnectTimeout = setTimeout(() => {
              this.init();
            }, 3000);
          }
        }
      });

      // Handle incoming & synced messages
      sock.ev.on('messages.upsert', async (mUpsert) => {
        // Ensure this socket is still active
        if (this.sock !== sock) return;

        const { messages, type } = mUpsert;
        if (!Array.isArray(messages)) return;

        for (const msg of messages) {
          if (!msg.key || !msg.key.remoteJid) continue;

          const messageId = msg.key.id;
          const rawJid = msg.key.remoteJid;
          // Filter out status broadcasts
          if (rawJid === 'status@broadcast') continue;

          const isFromMe = Boolean(msg.key.fromMe);
          const participant = msg.key.participant || '';

          // FORENSIC AUDIT: Stable composite deduplication key
          const stableKey = buildMessageDeduplicationKey(rawJid, messageId, participant, isFromMe);

          if (this.deduplicator.isDuplicate(stableKey) || this.deduplicator.isDuplicate(messageId)) {
            continue;
          }

          // Extract text content; skip if empty/system/unsupported
          const text = this.extractMessageText(msg);
          if (!text) continue;

          const timestamp = msg.messageTimestamp ? Number(msg.messageTimestamp) : Math.floor(Date.now() / 1000);
          const pushName = msg.pushName || '';
          const senderJid = participant || rawJid;

          // Resolve contact name safely
          let chatDisplayName = null;
          if (!isFromMe) {
            if (pushName && !isFallbackOrGenericName(pushName, rawJid)) {
              db.saveContact(rawJid, pushName);
              chatDisplayName = pushName.trim();
            } else {
              chatDisplayName = this.resolveContactName(rawJid);
            }
          }

          // Save to DB (chats table will be updated or created first to respect foreign key)
          const saveResult = db.saveMessage({
            id: messageId,
            chatId: rawJid,
            senderJid,
            text,
            isFromMe,
            timestamp,
            status: 'delivered',
            chatName: chatDisplayName
          });

          // If the message already existed in DB, DO NOT re-emit to Socket.IO!
          if (!saveResult.isNew) {
            continue;
          }

          // Realtime notification via Socket.IO
          if (this.io) {
            this.io.emit('new_message', {
              chatId: rawJid,
              message: saveResult.message
            });

            const chat = db.getChatById(rawJid);
            if (chat) {
              this.io.emit('chat_updated', chat);
            }
          }

          // SI BONTOT AUTO-REPLY TRIGGER
          // Only triggers for genuine new incoming messages from other contacts
          if (saveResult.isNew && !isFromMe) {
            this.processAutoReply(rawJid, messageId, text).catch(() => {});
          }
        }
      });
    } catch (err) {
      this.isConnecting = false;
      this.status = 'closed';
      this.emitStatus();
      this.clearReconnectTimer();
      this.reconnectTimeout = setTimeout(() => {
        this.init();
      }, 5000);
    }
  }

  /**
   * Process SI BONTOT Auto-Reply for an incoming message.
   * Includes anti-loop, anti-spam, and concurrency safety.
   */
  async processAutoReply(rawJid, messageId, text) {
    // 1. Must be enabled
    if (!this.autoReplyEnabled) return;

    // 1b. Controlled test isolation: if an allowlist is configured, ignore all unlisted contacts
    if (this.testAllowlist && this.testAllowlist.size > 0 && !this.matchesAllowlist(rawJid)) {
      return;
    }

    // 2. Must not be a group (Requirement: "fokus pada chat pribadi")
    if (rawJid.endsWith('@g.us')) return;

    // 3. Must not be status or system broadcast
    if (rawJid === 'status@broadcast') return;

    // 4. Must have valid non-empty text
    if (!text || typeof text !== 'string' || text.trim().length === 0) return;

    // 5. Check if already handled in DB
    if (db.isAutoReplyHandled(messageId)) return;

    // 6. Anti-spam: enforce minimum cooldown per chat (4 seconds)
    const lastReply = db.getLastAutoReplyTimestamp(rawJid);
    const now = Math.floor(Date.now() / 1000);
    if (lastReply && (now - lastReply) < 4) {
      return;
    }

    // 7. Atomic lock in database to prevent double execution on fast parallel events
    const locked = db.lockAutoReplyProcessing(messageId, rawJid);
    if (!locked) return;

    // 8. Check Ollama availability before proceeding
    const aiStatus = await checkOllamaStatus();
    if (!aiStatus.available || !aiStatus.activeModel) {
      db.markAutoReplyFailed(messageId, 'Ollama tidak tersedia saat pesan masuk.');
      return;
    }

    // 9. Notify frontend that SI BONTOT is thinking/processing
    if (this.io) {
      this.io.emit('auto_reply_processing', {
        chatId: rawJid,
        messageId,
        status: 'processing'
      });
    }

    try {
      // 10. Generate contextual reply with SI BONTOT character
      const contact = db.getContact(rawJid) || db.getChatById(rawJid);
      const senderName = contact?.name && !contact.name.includes('@') ? contact.name : null;

      const aiResult = await generateContextualReply({
        chatId: rawJid,
        currentMessageId: messageId,
        currentMessage: text,
        senderName
      });

      const replyText = aiResult.reply;
      if (!replyText || typeof replyText !== 'string' || replyText.trim().length === 0) {
        db.markAutoReplyFailed(messageId, 'Respons AI kosong.');
        if (this.io) {
          this.io.emit('auto_reply_processing', {
            chatId: rawJid,
            messageId,
            status: 'failed'
          });
        }
        return;
      }

      // Small natural pause (800ms)
      await new Promise(r => setTimeout(r, 800));

      // Re-verify auto-reply is still enabled
      if (!this.autoReplyEnabled) {
        db.markAutoReplyFailed(messageId, 'Auto-reply dinonaktifkan saat memproses.');
        return;
      }

      // 11. Send reply via existing sendMessage function
      await this.sendMessage(rawJid, replyText.trim());

      // 12. Record success in SQLite
      db.markAutoReplySuccess(messageId, replyText.trim());

      if (this.io) {
        this.io.emit('auto_reply_processing', {
          chatId: rawJid,
          messageId,
          status: 'done',
          reply: replyText.trim()
        });
      }
    } catch (err) {
      db.markAutoReplyFailed(messageId, err.message);
      if (this.io) {
        this.io.emit('auto_reply_processing', {
          chatId: rawJid,
          messageId,
          status: 'failed'
        });
      }
    }
  }

  extractMessageText(m) {
    if (!m || !m.message) return null;
    const msg = m.message;

    if (msg.conversation) return msg.conversation;
    if (msg.extendedTextMessage?.text) return msg.extendedTextMessage.text;
    if (msg.imageMessage?.caption) return `[Foto] ${msg.imageMessage.caption}`;
    if (msg.videoMessage?.caption) return `[Video] ${msg.videoMessage.caption}`;
    if (msg.documentMessage?.fileName) return `[Dokumen] ${msg.documentMessage.fileName}`;
    if (msg.buttonsResponseMessage?.selectedDisplayText) return msg.buttonsResponseMessage.selectedDisplayText;
    if (msg.templateButtonReplyMessage?.selectedDisplayText) return msg.templateButtonReplyMessage.selectedDisplayText;

    // Skip protocol, reaction, cipher, and headless system messages
    return null;
  }

  formatDestinationJid(to) {
    if (!to || typeof to !== 'string') {
      throw new Error('Nomor tujuan tidak valid.');
    }

    const trimmed = to.trim();

    // If it already has an @ domain, respect it (don't break @lid, @g.us, @s.whatsapp.net)
    if (trimmed.includes('@')) {
      return trimmed;
    }

    // Clean digits
    let digits = trimmed.replace(/\D/g, '');
    if (digits.startsWith('0')) {
      digits = '62' + digits.slice(1);
    }

    return `${digits}@s.whatsapp.net`;
  }

  async sendMessage(to, text) {
    if (this.status !== 'connected' || !this.sock) {
      throw new Error('WhatsApp belum terhubung. Silakan scan QR code terlebih dahulu.');
    }

    if (!text || typeof text !== 'string' || text.trim().length === 0) {
      throw new Error('Isi pesan tidak boleh kosong.');
    }

    const targetJid = this.formatDestinationJid(to);
    const sentMsg = await this.sock.sendMessage(targetJid, { text: text.trim() });

    const messageId = sentMsg.key.id;
    const timestamp = sentMsg.messageTimestamp ? Number(sentMsg.messageTimestamp) : Math.floor(Date.now() / 1000);

    // CRITICAL DEDUPLICATION:
    // Mark this message ID and composite key as seen in deduplicator immediately
    const stableKey = buildMessageDeduplicationKey(targetJid, messageId, '', true);
    this.deduplicator.add(messageId);
    this.deduplicator.add(stableKey);

    // Save sent message to local DB without overwriting existing contact name
    const saveResult = db.saveMessage({
      id: messageId,
      chatId: targetJid,
      senderJid: this.sock.user?.id || 'me',
      text: text.trim(),
      isFromMe: true,
      timestamp,
      status: 'sent',
      chatName: null // DO NOT overwrite contact name on outgoing messages
    });

    const savedMessage = saveResult.message;

    if (this.io) {
      this.io.emit('new_message', {
        chatId: targetJid,
        message: savedMessage
      });

      const updatedChat = db.getChatById(targetJid);
      if (updatedChat) {
        this.io.emit('chat_updated', updatedChat);
      }
    }

    return {
      jid: targetJid,
      message: savedMessage
    };
  }

  clearSessionFiles() {
    try {
      if (fs.existsSync(authDir)) {
        const files = fs.readdirSync(authDir);
        for (const file of files) {
          try {
            fs.unlinkSync(path.join(authDir, file));
          } catch (e) {}
        }
      }
    } catch (err) {}
  }

  async resetSession() {
    this.isExplicitLogout = true;
    this.clearReconnectTimer();
    this.cleanupSocket();
    this.clearSessionFiles();

    this.status = 'closed';
    this.currentUser = null;
    this.currentQrCode = null;
    this.currentRawQr = null;
    this.emitStatus();

    // Schedule re-init after brief delay so user can immediately scan new QR
    setTimeout(() => {
      this.isExplicitLogout = false;
      this.init();
    }, 1000);

    return { success: true, status: 'closed' };
  }
}

const waManager = new WhatsAppManager();

module.exports = waManager;
