const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

// Test database operations directly
const db = require('../server/db');
const { resolveSystemPrompt, DEFAULT_SYSTEM_PROMPT } = require('../server/ai');

test('Database: settings storage and retrieval', () => {
  const testKey = 'test_setting_key';
  const testValue = 'Test setting value 123';
  db.setSetting(testKey, testValue);
  assert.equal(db.getSetting(testKey), testValue);

  // Overwrite
  db.setSetting(testKey, 'New value');
  assert.equal(db.getSetting(testKey), 'New value');
});

test('Database: chat-before-message consistency with foreign keys enabled', () => {
  const testChatId = '628999999999@s.whatsapp.net';
  const testMsgId = `test-msg-${Date.now()}`;

  // Saving message should automatically ensure chat exists (satisfying foreign keys)
  db.saveMessage({
    id: testMsgId,
    chatId: testChatId,
    senderJid: testChatId,
    text: 'Halo ini tes konsistensi foreign key',
    isFromMe: false,
    timestamp: Math.floor(Date.now() / 1000),
    status: 'received',
    chatName: 'Kontak Tes'
  });

  const chat = db.getChatById(testChatId);
  assert.ok(chat, 'Chat harus tersimpan di tabel chats');
  assert.equal(chat.id, testChatId);
  assert.equal(chat.unread_count, 1, 'Unread count bertambah untuk pesan masuk');

  const messages = db.getMessages(testChatId);
  assert.ok(messages.length > 0, 'Pesan harus tersimpan di tabel messages');
  assert.equal(messages[messages.length - 1].id, testMsgId);

  // Reset unread
  db.resetChatUnread(testChatId);
  const updatedChat = db.getChatById(testChatId);
  assert.equal(updatedChat.unread_count, 0, 'Unread count berhasil di-reset');
});

test('AI: system prompt precedence order', () => {
  // 1. When request prompt provided, it takes highest precedence
  const p1 = resolveSystemPrompt('Custom request prompt');
  assert.equal(p1, 'Custom request prompt');

  // 2. When request prompt is empty, fallback to DB setting
  db.setSetting('ai_system_prompt', 'DB saved prompt');
  const p2 = resolveSystemPrompt('');
  assert.equal(p2, 'DB saved prompt');

  // 3. When DB setting is reset, fallback to DEFAULT_SYSTEM_PROMPT
  db.setSetting('ai_system_prompt', '');
  const p3 = resolveSystemPrompt('');
  assert.equal(p3, DEFAULT_SYSTEM_PROMPT);
});
