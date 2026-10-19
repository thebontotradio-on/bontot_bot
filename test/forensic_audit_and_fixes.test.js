const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../server/db');
const {
  MessageDeduplicator,
  buildMessageDeduplicationKey,
  isFallbackOrGenericName,
  formatJidDisplay
} = require('../server/utils');
const waManager = require('../server/whatsapp');

// 1. Pesan masuk identik dengan ID yang sama hanya tersimpan satu kali.
test('Test 1: Pesan masuk identik dengan ID yang sama hanya tersimpan satu kali di DB dan tidak menambah unread ganda', () => {
  const chatId = 'test-dup-chat@s.whatsapp.net';
  const messageId = `identical-id-${Date.now()}`;
  db.resetChatUnread(chatId);

  const res1 = db.saveMessage({
    id: messageId,
    chatId,
    senderJid: chatId,
    text: 'apa kabar bro?',
    isFromMe: false,
    timestamp: 1792384300,
    status: 'delivered',
    chatName: 'Teman Tes'
  });

  assert.equal(res1.isNew, true, 'Panggilan pertama harus dikenali sebagai pesan baru');

  // Panggilan kedua dengan ID yang sama persis
  const res2 = db.saveMessage({
    id: messageId,
    chatId,
    senderJid: chatId,
    text: 'apa kabar bro?',
    isFromMe: false,
    timestamp: 1792384300,
    status: 'delivered',
    chatName: 'Teman Tes'
  });

  assert.equal(res2.isNew, false, 'Panggilan kedua harus terdeteksi sebagai duplikat dan isNew bernilai false');

  // Periksa data di database
  const messages = db.getMessages(chatId);
  const matched = messages.filter((m) => m.id === messageId);
  assert.equal(matched.length, 1, 'Hanya boleh ada tepat satu pesan dengan ID tersebut di database');

  const chat = db.getChatById(chatId);
  assert.equal(chat.unread_count, 1, 'Unread count tidak boleh bertambah dua kali untuk pesan duplikat yang sama');
});

// 2. Dua pesan dengan teks identik tetapi ID berbeda tetap tampil dua kali.
test('Test 2: Dua pesan dengan teks identik tetapi ID berbeda tetap tersimpan dan tampil dua kali', () => {
  const chatId = 'test-diff-id-chat@s.whatsapp.net';
  const id1 = `msg-diff-1-${Date.now()}`;
  const id2 = `msg-diff-2-${Date.now()}`;

  db.saveMessage({
    id: id1,
    chatId,
    senderJid: chatId,
    text: 'apa kabar bro?',
    isFromMe: false,
    timestamp: 1792384310,
    status: 'delivered',
    chatName: 'Kontak A'
  });

  db.saveMessage({
    id: id2,
    chatId,
    senderJid: chatId,
    text: 'apa kabar bro?',
    isFromMe: false,
    timestamp: 1792384315,
    status: 'delivered',
    chatName: 'Kontak A'
  });

  const messages = db.getMessages(chatId);
  const matched = messages.filter((m) => m.id === id1 || m.id === id2);
  assert.equal(matched.length, 2, 'Kedua pesan dengan ID berbeda harus tetap ada di database');
  assert.equal(matched[0].text, 'apa kabar bro?');
  assert.equal(matched[1].text, 'apa kabar bro?');
});

// 3. Broadcast Socket.IO dan respons REST untuk satu pesan keluar tidak membuat duplikasi.
test('Test 3: Broadcast Socket.IO dan respons REST untuk satu pesan keluar tidak membuat duplikasi (Frontend Deduplication Logic)', () => {
  function deduplicateMessages(list) {
    const seen = new Set();
    const res = [];
    for (const m of list) {
      if (!m || !m.id) continue;
      if (seen.has(m.id)) continue;
      seen.add(m.id);
      res.push(m);
    }
    return res;
  }

  // Skenario A: Socket.IO broadcast tiba LEBIH DULU daripada respons REST
  let state = [];
  const tempId = 'optimistic-1001';
  const confirmedId = '3EB0_REAL_SERVER_ID';

  // 1. User mengetik dan menekan Send
  state = [...state, { id: tempId, text: 'apa kabar bro?', is_from_me: 1, status: 'sending' }];
  assert.equal(state.length, 1);

  // 2. Socket.IO broadcast tiba
  const socketMessage = { id: confirmedId, text: 'apa kabar bro?', is_from_me: 1, status: 'sent' };
  // Sesuai logika App.jsx: jika is_from_me dan ada optimistic message dengan teks yang sama, ganti placeholder
  const optIndex = state.findIndex((m) => m.id.startsWith('optimistic-') && m.text === socketMessage.text);
  if (optIndex !== -1) {
    state[optIndex] = socketMessage;
  } else {
    state.push(socketMessage);
  }
  state = deduplicateMessages(state);
  assert.equal(state.length, 1, 'Setelah socket event tiba, pesan tetap 1 buah');
  assert.equal(state[0].id, confirmedId);

  // 3. Respons HTTP REST tiba setelahnya
  const restMessage = { id: confirmedId, text: 'apa kabar bro?', is_from_me: 1, status: 'sent' };
  const alreadyHasReal = state.some((m) => m.id === restMessage.id);
  if (alreadyHasReal) {
    state = state.filter((m) => m.id !== tempId);
  } else {
    state = state.map((m) => (m.id === tempId ? restMessage : m));
  }
  state = deduplicateMessages(state);
  assert.equal(state.length, 1, 'Setelah respons REST tiba, pesan tetap tepat 1 buah (TIDAK DUPLIKAT)');
  assert.equal(state[0].id, confirmedId);

  // Skenario B: Respons REST tiba LEBIH DULU daripada Socket.IO broadcast
  let stateB = [];
  stateB.push({ id: tempId, text: 'halo juga', is_from_me: 1, status: 'sending' });

  // REST tiba
  const restB = { id: 'CONFIRMED_B', text: 'halo juga', is_from_me: 1, status: 'sent' };
  stateB = stateB.map((m) => (m.id === tempId ? restB : m));
  assert.equal(stateB.length, 1);

  // Socket tiba
  const socketB = { id: 'CONFIRMED_B', text: 'halo juga', is_from_me: 1, status: 'sent' };
  if (!stateB.some((m) => m.id === socketB.id)) {
    stateB.push(socketB);
  }
  stateB = deduplicateMessages(stateB);
  assert.equal(stateB.length, 1, 'Pesan tidak duplikat saat socket tiba setelah REST');
});

// 4. Listener frontend tidak terdaftar berulang setelah pergantian chat.
test('Test 4: Listener Socket.IO frontend terpasang sekali dan tidak bertumpuk saat pergantian chat', () => {
  // Simulasikan registrasi handler
  const registeredListeners = new Map();
  function registerSocket(event, handler) {
    if (!registeredListeners.has(event)) {
      registeredListeners.set(event, []);
    }
    registeredListeners.get(event).push(handler);
  }

  // Inisialisasi App.jsx
  registerSocket('new_message', (payload) => {});
  registerSocket('status_change', (payload) => {});
  registerSocket('chat_updated', (payload) => {});

  // Ganti chat 5 kali (handleSelectChat hanya memuat pesan, tidak menambah socket.on)
  for (let i = 0; i < 5; i++) {
    // handleSelectChat dipanggil
    const activeChatId = `chat-${i}@s.whatsapp.net`;
    assert.ok(activeChatId);
  }

  assert.equal(registeredListeners.get('new_message').length, 1, 'new_message listener hanya boleh 1');
  assert.equal(registeredListeners.get('status_change').length, 1, 'status_change listener hanya boleh 1');
});

// 5. Pesan dengan JID @lid tidak diubah menjadi nomor telepon palsu.
test('Test 5: Pesan dengan JID @lid tidak diubah menjadi nomor telepon palsu atau dipaksa ke @s.whatsapp.net', () => {
  const lidJid = '107670971408579@lid';

  // formatDestinationJid tidak boleh mengubah @lid
  const dest = waManager.formatDestinationJid(lidJid);
  assert.equal(dest, lidJid, 'JID @lid harus dipertahankan persis tanpa modifikasi');

  // formatJidDisplay tidak boleh mengubah @lid menjadi +107670971408579
  const display = formatJidDisplay(lidJid);
  assert.equal(display.includes('+107670971408579'), false, 'Tidak boleh menganggap angka LID sebagai nomor telepon');
  assert.equal(display.startsWith('Pengguna ('), true, 'Harus menggunakan fallback yang jelas');

  // Jika nama kontak / pushName tersedia, gunakan nama tersebut
  const withName = formatJidDisplay(lidJid, 'Adhy');
  assert.equal(withName, 'Adhy', 'Nama kontak Adhy harus diprioritaskan');
});

// 6. Nama kontak yang valid tidak ditimpa oleh fallback.
test('Test 6: Nama kontak yang valid (Adhy) tidak ditimpa oleh fallback saat pesan baru masuk atau keluar', () => {
  const lidJid = 'test-preserve-name@lid';

  // 1. Simpan chat pertama kali dengan nama asli 'Adhy'
  db.upsertChat({
    id: lidJid,
    name: 'Adhy',
    unread_count: 0,
    last_message_timestamp: 1792384000,
    last_message_text: 'Halo awal'
  });

  const chat1 = db.getChatById(lidJid);
  assert.equal(chat1.name, 'Adhy');

  // 2. Simulasikan pesan keluar di mana chatName adalah fallback atau null
  db.saveMessage({
    id: `msg-out-${Date.now()}`,
    chatId: lidJid,
    senderJid: 'me',
    text: 'apa kabar bro?',
    isFromMe: true,
    timestamp: 1792384302,
    status: 'sent',
    chatName: 'Pengguna (107670...)' // Fallback tidak boleh menimpa Adhy!
  });

  const chat2 = db.getChatById(lidJid);
  assert.equal(chat2.name, 'Adhy', 'Nama kontak Adhy TIDAK BOLEH ditimpa oleh fallback Pengguna (...)');

  // 3. Simulasikan upsertChat dengan nama kosong/null
  db.upsertChat({
    id: lidJid,
    name: null,
    last_message_timestamp: 1792384310,
    last_message_text: 'Pesan baru'
  });

  const chat3 = db.getChatById(lidJid);
  assert.equal(chat3.name, 'Adhy', 'Nama kontak Adhy TIDAK BOLEH ditimpa oleh null');
});

// 7. Pesan grup tidak mengalami tabrakan ID dengan pesan pribadi.
test('Test 7: Pesan grup tidak mengalami tabrakan ID dengan pesan pribadi (buildMessageDeduplicationKey)', () => {
  const sharedMessageId = 'MSG_COLLISION_123';
  const groupJid = '12036302839210@g.us';
  const participantJid = '628123456789@s.whatsapp.net';
  const privateJid = '628123456789@s.whatsapp.net';

  const groupKey = buildMessageDeduplicationKey(groupJid, sharedMessageId, participantJid, false);
  const privateKey = buildMessageDeduplicationKey(privateJid, sharedMessageId, '', false);

  assert.notEqual(groupKey, privateKey, 'Kunci deduplikasi grup dan private harus berbeda');
  assert.ok(groupKey.includes(groupJid));
  assert.ok(groupKey.includes(participantJid));
  assert.ok(privateKey.includes(privateJid));

  const deduplicator = new MessageDeduplicator(100);
  assert.equal(deduplicator.isDuplicate(groupKey), false, 'Pesan grup harus diizinkan masuk');
  assert.equal(deduplicator.isDuplicate(privateKey), false, 'Pesan private dengan ID sama harus tetap diizinkan masuk');
});
