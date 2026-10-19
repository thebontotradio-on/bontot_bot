const path = require('path');
const fs = require('fs');
const Database = require('better-sqlite3');
const { isFallbackOrGenericName } = require('./utils');

const dataDir = path.join(__dirname, 'data');
if (!fs.existsSync(dataDir)) {
  fs.mkdirSync(dataDir, { recursive: true });
}

const dbPath = path.join(dataDir, 'wabontot.db');
const db = new Database(dbPath);

// Enable foreign keys
db.pragma('foreign_keys = ON');

// Initialize schema
db.exec(`
  CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
  );

  CREATE TABLE IF NOT EXISTS chats (
    id TEXT PRIMARY KEY,
    name TEXT,
    unread_count INTEGER DEFAULT 0,
    last_message_timestamp INTEGER DEFAULT 0,
    last_message_text TEXT,
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
  );

  CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    chat_id TEXT NOT NULL,
    sender_jid TEXT,
    text TEXT,
    is_from_me INTEGER DEFAULT 0,
    timestamp INTEGER NOT NULL,
    status TEXT DEFAULT 'sent',
    FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE
  );

  CREATE TABLE IF NOT EXISTS contacts (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT,
    updated_at INTEGER DEFAULT (strftime('%s', 'now'))
  );

  CREATE TABLE IF NOT EXISTS auto_reply_logs (
    message_id TEXT PRIMARY KEY,
    chat_id TEXT NOT NULL,
    status TEXT NOT NULL, -- 'processing', 'replied', 'failed', 'skipped'
    reply_text TEXT,
    created_at INTEGER NOT NULL,
    replied_at INTEGER
  );

  CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id);
  CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);
  CREATE INDEX IF NOT EXISTS idx_contacts_id ON contacts(id);
  CREATE INDEX IF NOT EXISTS idx_auto_reply_chat_id ON auto_reply_logs(chat_id);
`);

// Prepared statements
const stmts = {
  getSetting: db.prepare('SELECT value FROM settings WHERE key = ?'),
  setSetting: db.prepare(`
    INSERT INTO settings (key, value) VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
  `),
  
  getAllChats: db.prepare('SELECT * FROM chats ORDER BY last_message_timestamp DESC, updated_at DESC'),
  getChat: db.prepare('SELECT * FROM chats WHERE id = ?'),
  
  upsertChat: db.prepare(`
    INSERT INTO chats (id, name, unread_count, last_message_timestamp, last_message_text, updated_at)
    VALUES (@id, @name, @unread_count, @last_message_timestamp, @last_message_text, strftime('%s', 'now'))
    ON CONFLICT(id) DO UPDATE SET
      name = CASE
        -- 1. If incoming name is non-null, non-empty, and NOT a generic fallback, update to it
        WHEN excluded.name IS NOT NULL 
          AND TRIM(excluded.name) != '' 
          AND excluded.name NOT LIKE 'Pengguna (%' 
          AND excluded.name NOT LIKE 'User (%'
          AND excluded.name != chats.id
          AND excluded.name != excluded.id
        THEN excluded.name

        -- 2. If existing chat name is already a valid name, PRESERVE IT
        WHEN chats.name IS NOT NULL 
          AND TRIM(chats.name) != '' 
          AND chats.name NOT LIKE 'Pengguna (%' 
          AND chats.name NOT LIKE 'User (%'
          AND chats.name != chats.id
        THEN chats.name

        -- 3. Otherwise use incoming name if available, else keep existing
        ELSE COALESCE(excluded.name, chats.name)
      END,
      unread_count = COALESCE(excluded.unread_count, chats.unread_count),
      last_message_timestamp = CASE 
        WHEN excluded.last_message_timestamp > chats.last_message_timestamp 
        THEN excluded.last_message_timestamp 
        ELSE chats.last_message_timestamp 
      END,
      last_message_text = COALESCE(excluded.last_message_text, chats.last_message_text),
      updated_at = strftime('%s', 'now')
  `),

  setChatNameExplicit: db.prepare(`
    UPDATE chats 
    SET name = ?, updated_at = strftime('%s', 'now') 
    WHERE id = ?
  `),
  
  incrementUnread: db.prepare(`
    UPDATE chats 
    SET unread_count = unread_count + 1, updated_at = strftime('%s', 'now')
    WHERE id = ?
  `),

  resetUnread: db.prepare(`
    UPDATE chats 
    SET unread_count = 0, updated_at = strftime('%s', 'now')
    WHERE id = ?
  `),

  getMessageById: db.prepare('SELECT * FROM messages WHERE id = ?'),

  updateMessageStatus: db.prepare(`
    UPDATE messages SET status = ? WHERE id = ?
  `),

  insertMessage: db.prepare(`
    INSERT INTO messages (id, chat_id, sender_jid, text, is_from_me, timestamp, status)
    VALUES (@id, @chat_id, @sender_jid, @text, @is_from_me, @timestamp, @status)
    ON CONFLICT(id) DO UPDATE SET
      status = excluded.status,
      text = COALESCE(excluded.text, messages.text)
  `),

  getMessagesByChat: db.prepare(`
    SELECT * FROM messages 
    WHERE chat_id = ? 
    ORDER BY timestamp ASC 
    LIMIT ?
  `),

  getRecentMessagesForContext: db.prepare(`
    SELECT * FROM (
      SELECT * FROM messages 
      WHERE chat_id = ? 
      ORDER BY timestamp DESC, id DESC 
      LIMIT ?
    ) ORDER BY timestamp ASC, id ASC
  `),

  getContact: db.prepare('SELECT * FROM contacts WHERE id = ?'),

  upsertContact: db.prepare(`
    INSERT INTO contacts (id, name, phone, updated_at)
    VALUES (?, ?, ?, strftime('%s', 'now'))
    ON CONFLICT(id) DO UPDATE SET
      name = excluded.name,
      phone = COALESCE(excluded.phone, contacts.phone),
      updated_at = strftime('%s', 'now')
  `),

  // Auto-Reply Tracking prepared statements
  getAutoReplyLog: db.prepare('SELECT * FROM auto_reply_logs WHERE message_id = ?'),

  insertAutoReplyLock: db.prepare(`
    INSERT INTO auto_reply_logs (message_id, chat_id, status, created_at)
    VALUES (?, ?, 'processing', strftime('%s', 'now'))
  `),

  markAutoReplySuccess: db.prepare(`
    UPDATE auto_reply_logs 
    SET status = 'replied', reply_text = ?, replied_at = strftime('%s', 'now')
    WHERE message_id = ?
  `),

  markAutoReplyError: db.prepare(`
    UPDATE auto_reply_logs 
    SET status = 'failed', reply_text = ?, replied_at = strftime('%s', 'now')
    WHERE message_id = ?
  `),

  getLastAutoReplyTime: db.prepare(`
    SELECT MAX(replied_at) as last_time 
    FROM auto_reply_logs 
    WHERE chat_id = ? AND status = 'replied'
  `),

  countActiveAutoReplyProcessing: db.prepare(`
    SELECT COUNT(*) as count 
    FROM auto_reply_logs 
    WHERE status = 'processing' AND created_at > (strftime('%s', 'now') - 60)
  `)
};

function clearAllData() {
  db.exec('DELETE FROM messages; DELETE FROM chats; DELETE FROM contacts; DELETE FROM auto_reply_logs;');
}

function getSetting(key, defaultValue = null) {
  const row = stmts.getSetting.get(key);
  return row ? row.value : defaultValue;
}

function setSetting(key, value) {
  stmts.setSetting.run(key, String(value));
}

function getChats() {
  return stmts.getAllChats.all();
}

function getChatById(id) {
  return stmts.getChat.get(id);
}

function ensureChatExists(chatId, fallbackName = '') {
  const existing = stmts.getChat.get(chatId);
  if (!existing) {
    // Check if we have a contact name
    let effectiveName = fallbackName || chatId;
    const contact = stmts.getContact.get(chatId);
    if (contact && contact.name) {
      effectiveName = contact.name;
    }

    stmts.upsertChat.run({
      id: chatId,
      name: effectiveName,
      unread_count: 0,
      last_message_timestamp: Math.floor(Date.now() / 1000),
      last_message_text: ''
    });
  }
}

function upsertChat(chat) {
  stmts.upsertChat.run({
    id: chat.id,
    name: chat.name !== undefined ? chat.name : null,
    unread_count: chat.unread_count !== undefined ? chat.unread_count : 0,
    last_message_timestamp: chat.last_message_timestamp || Math.floor(Date.now() / 1000),
    last_message_text: chat.last_message_text || ''
  });
}

function updateChatName(chatId, newName) {
  if (!chatId || !newName) return;
  if (isFallbackOrGenericName(newName, chatId)) return;
  stmts.setChatNameExplicit.run(newName.trim(), chatId);
}

function resetChatUnread(chatId) {
  stmts.resetUnread.run(chatId);
}

function saveContact(id, name, phone = null) {
  if (!id || !name) return;
  if (isFallbackOrGenericName(name, id)) return;

  stmts.upsertContact.run(id, name.trim(), phone || null);

  // If a chat already exists with this ID, ensure its name is updated
  const existingChat = stmts.getChat.get(id);
  if (existingChat) {
    updateChatName(id, name.trim());
  }
}

function getContact(id) {
  return stmts.getContact.get(id);
}

/**
 * Save message with deduplication protection.
 * Returns { isNew: boolean, message: object }
 */
function saveMessage({ id, chatId, senderJid, text, isFromMe, timestamp, status, chatName }) {
  // Check if message with this ID already exists
  const existing = stmts.getMessageById.get(id);
  if (existing) {
    if (status && status !== existing.status) {
      stmts.updateMessageStatus.run(status, id);
      existing.status = status;
    }
    return { isNew: false, message: existing };
  }

  // Ensure chat exists before inserting message (respect foreign key)
  ensureChatExists(chatId, chatName);

  stmts.insertMessage.run({
    id,
    chat_id: chatId,
    sender_jid: senderJid || null,
    text: text || '',
    is_from_me: isFromMe ? 1 : 0,
    timestamp: timestamp || Math.floor(Date.now() / 1000),
    status: status || 'sent'
  });

  // Only pass chatName if it's not a generic fallback and not an outgoing message
  let nameToPass = null;
  if (!isFromMe && chatName && !isFallbackOrGenericName(chatName, chatId)) {
    nameToPass = chatName;
  }

  // Update chat summary
  stmts.upsertChat.run({
    id: chatId,
    name: nameToPass,
    unread_count: null,
    last_message_timestamp: timestamp || Math.floor(Date.now() / 1000),
    last_message_text: text || ''
  });

  if (!isFromMe) {
    stmts.incrementUnread.run(chatId);
  }

  const savedMsg = {
    id,
    chat_id: chatId,
    sender_jid: senderJid || null,
    text: text || '',
    is_from_me: isFromMe ? 1 : 0,
    timestamp: timestamp || Math.floor(Date.now() / 1000),
    status: status || 'sent'
  };

  return { isNew: true, message: savedMsg };
}

function getMessages(chatId, limit = 100) {
  return stmts.getMessagesByChat.all(chatId, limit);
}

function getRecentMessagesForContext(chatId, limit = 6) {
  return stmts.getRecentMessagesForContext.all(chatId, limit);
}

function getMessage(id) {
  return stmts.getMessageById.get(id);
}

// ==========================================
// AUTO-REPLY TRACKING FUNCTIONS
// ==========================================

/**
 * Checks if message was already processed or is currently being processed.
 */
function isAutoReplyHandled(messageId) {
  if (!messageId) return false;
  const row = stmts.getAutoReplyLog.get(messageId);
  return Boolean(row);
}

/**
 * Atomically attempt to acquire processing lock for an incoming message.
 * Returns true if locked successfully, false if already locked/processed.
 */
function lockAutoReplyProcessing(messageId, chatId) {
  if (!messageId || !chatId) return false;
  try {
    stmts.insertAutoReplyLock.run(messageId, chatId);
    return true;
  } catch (err) {
    // Unique constraint violation: already being processed or replied
    return false;
  }
}

function markAutoReplySuccess(messageId, replyText) {
  try {
    stmts.markAutoReplySuccess.run(replyText || '', messageId);
  } catch (err) {}
}

function markAutoReplyFailed(messageId, errorMsg) {
  try {
    stmts.markAutoReplyError.run(errorMsg || 'Unknown error', messageId);
  } catch (err) {}
}

function getLastAutoReplyTimestamp(chatId) {
  if (!chatId) return 0;
  const row = stmts.getLastAutoReplyTime.get(chatId);
  return (row && row.last_time) ? Number(row.last_time) : 0;
}

function getActiveAutoReplyProcessingCount() {
  const row = stmts.countActiveAutoReplyProcessing.get();
  return (row && row.count) ? Number(row.count) : 0;
}

module.exports = {
  db,
  getSetting,
  setSetting,
  getChats,
  getChatById,
  ensureChatExists,
  upsertChat,
  updateChatName,
  resetChatUnread,
  saveContact,
  getContact,
  saveMessage,
  getMessages,
  getRecentMessagesForContext,
  getMessage,
  clearAllData,
  isAutoReplyHandled,
  lockAutoReplyProcessing,
  markAutoReplySuccess,
  markAutoReplyFailed,
  getLastAutoReplyTimestamp,
  getActiveAutoReplyProcessingCount
};
