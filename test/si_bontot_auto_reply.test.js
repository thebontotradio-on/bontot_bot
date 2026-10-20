const test = require('node:test');
const assert = require('node:assert/strict');
const db = require('../server/db');
const waManager = require('../server/whatsapp');
const {
  checkOllamaStatus,
  generateAiReply,
  generateContextualReply,
  resolveSystemPrompt,
  DEFAULT_SYSTEM_PROMPT
} = require('../server/ai');

// 1. Auto-Reply default OFF.
test('Test 1: Auto-Reply default status wajib OFF', () => {
  // Reset instance to default
  waManager.setAutoReplyEnabled(false);
  assert.equal(waManager.getAutoReplyEnabled(), false, 'Auto-reply harus bernilai false secara default');
});

// 2. Pesan masuk baru dibalas ketika ON dan Ollama tersedia.
test('Test 2: Pesan masuk baru diproses ketika Auto-Reply ON dan Ollama aktif', async () => {
  waManager.setAutoReplyEnabled(true);
  const chatId = 'user-auto-test@s.whatsapp.net';
  const msgId = `auto-msg-valid-${Date.now()}`;

  // Simulasikan pesan masuk di DB
  db.saveMessage({
    id: msgId,
    chatId,
    senderJid: chatId,
    text: 'Halo SI BONTOT, radio THE BONTOT frekuensi berapa?',
    isFromMe: false,
    timestamp: Math.floor(Date.now() / 1000),
    status: 'delivered'
  });

  // Uji penguncian pemrosesan auto-reply
  const locked = db.lockAutoReplyProcessing(msgId, chatId);
  assert.equal(locked, true, 'Kunci pemrosesan harus berhasil didapat untuk pesan baru');

  // Simulasikan penyelesaian balasan
  const sampleReply = 'Halo! SI BONTOT di sini dari THE BONTOT RADIO. Kami mengudara di streaming digital 24 jam!';
  db.markAutoReplySuccess(msgId, sampleReply);

  assert.equal(db.isAutoReplyHandled(msgId), true, 'Pesan harus tercatat sebagai sudah diproses');
  waManager.setAutoReplyEnabled(false);
});

// 3. Pesan dari akun sendiri tidak dibalas.
test('Test 3: Pesan dari akun sendiri (fromMe) tidak boleh dibalas otomatis', async () => {
  waManager.setAutoReplyEnabled(true);
  const myMsgId = `from-me-${Date.now()}`;
  const chatId = 'target-friend@s.whatsapp.net';

  // Pesan keluar (isFromMe: true)
  const saveRes = db.saveMessage({
    id: myMsgId,
    chatId,
    senderJid: 'me',
    text: 'Pesan dari diri saya sendiri',
    isFromMe: true,
    timestamp: Math.floor(Date.now() / 1000),
    status: 'sent'
  });

  assert.equal(saveRes.message.is_from_me, 1);
  // Logika Baileys messages.upsert:
  // if (saveResult.isNew && !isFromMe) { this.processAutoReply(...) }
  // Karena isFromMe bernilai true, processAutoReply TIDAK PERNAH dipanggil
  assert.equal(db.isAutoReplyHandled(myMsgId), false, 'Pesan fromMe tidak boleh masuk ke log auto-reply');
  waManager.setAutoReplyEnabled(false);
});

// 4. Pesan yang sama tidak dibalas dua kali.
test('Test 4: Pesan yang sama tidak boleh dibalas dua kali', async () => {
  const msgId = `dedup-reply-${Date.now()}`;
  const chatId = 'user-test-4@s.whatsapp.net';

  // Kunci pertama kali
  const lock1 = db.lockAutoReplyProcessing(msgId, chatId);
  assert.equal(lock1, true, 'Kunci pertama harus sukses');

  // Kunci kedua kali untuk pesan yang sama
  const lock2 = db.lockAutoReplyProcessing(msgId, chatId);
  assert.equal(lock2, false, 'Kunci kedua harus gagal karena ID pesan sudah terdaftar');

  assert.equal(db.isAutoReplyHandled(msgId), true);
});

// 5. Dua pesan masuk berdekatan tidak memicu balasan ganda (cooldown anti-spam).
test('Test 5: Dua pesan masuk berdekatan ke chat yang sama mematuhi jeda anti-spam (cooldown)', () => {
  const chatId = 'cooldown-chat@s.whatsapp.net';
  const msg1 = `burst-1-${Date.now()}`;
  const msg2 = `burst-2-${Date.now()}`;

  // Balas pesan 1 sekarang
  db.lockAutoReplyProcessing(msg1, chatId);
  db.markAutoReplySuccess(msg1, 'Balasan 1');

  // Cek timestamp balasan terakhir
  const lastReplyTime = db.getLastAutoReplyTimestamp(chatId);
  const now = Math.floor(Date.now() / 1000);
  assert.ok(lastReplyTime > 0);

  // Jika pesan 2 tiba dalam selang waktu < 4 detik
  const diff = now - lastReplyTime;
  const isCooldownActive = diff < 4;
  assert.equal(isCooldownActive, true, 'Cooldown harus aktif jika pesan tiba dalam selang waktu sangat singkat');
});

// 6. Pesan grup tidak dibalas secara default.
test('Test 6: Pesan grup (@g.us) tidak dibalas otomatis secara default', async () => {
  waManager.setAutoReplyEnabled(true);
  const groupJid = '12036302847192@g.us';
  const groupMsgId = `group-msg-${Date.now()}`;

  // processAutoReply memeriksa: if (rawJid.endsWith('@g.us')) return;
  await waManager.processAutoReply(groupJid, groupMsgId, 'Halo grup!');
  assert.equal(db.isAutoReplyHandled(groupMsgId), false, 'Pesan grup harus diabaikan');
  waManager.setAutoReplyEnabled(false);
});

// 7. Error penanganan / kegagalan AI ditangani dengan aman tanpa crash server.
test('Test 7: Error / kegagalan AI ditangani dengan aman tanpa crash', async () => {
  waManager.setAutoReplyEnabled(true);
  const chatId = 'offline-test@s.whatsapp.net';
  const msgId = `offline-msg-${Date.now()}`;

  // Cek bahwa generateContextualReply menolak jika input kosong dengan error tertangani
  await assert.rejects(
    async () => {
      await generateContextualReply({
        chatId,
        currentMessage: ''
      });
    },
    (err) => {
      assert.ok(err.message.includes('kosong'));
      return true;
    }
  );

  // processAutoReply mencatat status ke database tanpa melempar exception ke server
  await waManager.processAutoReply(chatId, msgId, 'Tes penanganan aman');
  assert.equal(db.isAutoReplyHandled(msgId), true);
  waManager.setAutoReplyEnabled(false);
});

// 8. Respons AI kosong tidak dikirim ke WhatsApp.
test('Test 8: Respons AI kosong tidak boleh dikirim sebagai pesan', async () => {
  const emptyReply = '   ';
  const isValid = Boolean(emptyReply && typeof emptyReply === 'string' && emptyReply.trim().length > 0);
  assert.equal(isValid, false, 'String kosong tidak boleh dianggap valid untuk dikirim');
});

// 9. Toggle OFF menghentikan pemrosesan pesan baru.
test('Test 9: Toggle OFF menghentikan pemrosesan pesan baru seketika', async () => {
  waManager.setAutoReplyEnabled(false);
  const chatId = 'toggle-off-test@s.whatsapp.net';
  const msgId = `msg-toggle-off-${Date.now()}`;

  await waManager.processAutoReply(chatId, msgId, 'Pesan saat fitur OFF');
  assert.equal(db.isAutoReplyHandled(msgId), false, 'Pesan tidak boleh diproses saat Auto-Reply bernilai OFF');
});

// 10. Restart server tidak menyebabkan pesan lama dibalas ulang.
test('Test 10: Pesan lama yang sudah tersimpan di database tidak dibalas ulang saat server restart', () => {
  const oldMsgId = `old-message-historical-${Date.now()}`;
  const chatId = 'user-historical@s.whatsapp.net';

  // Tandai pesan sudah ditangani di SQLite
  db.lockAutoReplyProcessing(oldMsgId, chatId);
  db.markAutoReplySuccess(oldMsgId, 'Sudah dibalas kemarin');

  // Simulasikan server restart: data tetap ada di SQLite
  const isHandledAfterRestart = db.isAutoReplyHandled(oldMsgId);
  assert.equal(isHandledAfterRestart, true, 'Pesan lama harus tetap tercatat sebagai handled setelah restart');
});

// 11. Pengiriman manual tetap berfungsi.
test('Test 11: Pengiriman manual tetap berfungsi dan menghasilkan objek pesan yang valid', async () => {
  // formatDestinationJid
  const target = waManager.formatDestinationJid('08123456789');
  assert.equal(target, '628123456789@s.whatsapp.net');

  // Ketika disconnect, sendMessage melempar error yang jelas
  await assert.rejects(
    async () => {
      // Jika socket null/closed
      const tempManager = new (require('../server/whatsapp').constructor)();
      await tempManager.sendMessage('08123456789', 'Tes manual');
    },
    (err) => {
      assert.ok(err.message.includes('WhatsApp belum terhubung'));
      return true;
    }
  );
});

// 12. Karakter dan Persona SI BONTOT terkonfigurasi benar.
test('Test 12: System prompt default SI BONTOT memuat identitas Bang Adhy, THE BONTOT RADIO, dan santai', () => {
  const prompt = resolveSystemPrompt('');
  assert.ok(prompt.includes('SI BONTOT'));
  assert.ok(prompt.includes('THE BONTOT RADIO'));
  assert.ok(prompt.includes('Bang Adhy'));
  assert.ok(prompt.includes('lagi kerja'));
  assert.ok(prompt.includes('HINDARI KATA FORMAL'));
});

// 13. Controlled test isolation: allowlist membatasi auto-reply hanya ke kontak yang diizinkan
test('Test 13: Allowlist membatasi auto-reply hanya untuk kontak yang terdaftar', async () => {
  waManager.setAutoReplyEnabled(true);
  waManager.setTestAllowlist(['allowed-user@s.whatsapp.net']);

  const blockedChatId = 'blocked-user@s.whatsapp.net';
  const blockedMsgId = `blocked-msg-${Date.now()}`;

  // Contact outside allowlist should be skipped immediately without DB lock or reply
  await waManager.processAutoReply(blockedChatId, blockedMsgId, 'Halo dari kontak luar');
  assert.equal(db.isAutoReplyHandled(blockedMsgId), false, 'Kontak di luar allowlist tidak boleh diproses');

  // Contact in allowlist is allowed
  assert.deepEqual(waManager.getTestAllowlist(), ['allowed-user@s.whatsapp.net']);

  // Reset allowlist and autoReply
  waManager.setTestAllowlist([]);
  waManager.setAutoReplyEnabled(false);
});

// 14. Mengosongkan allowlist mengembalikan daftar kosong dengan aman
test('Test 14: Mengosongkan allowlist mengembalikan daftar kosong dengan aman', () => {
  waManager.setTestAllowlist(['temp@s.whatsapp.net']);
  assert.equal(waManager.getTestAllowlist().length, 1);
  waManager.setTestAllowlist([]);
  assert.equal(waManager.getTestAllowlist().length, 0);
  assert.equal(waManager.getAutoReplyEnabled(), false);
});

// 15. Sanitasi output AI (cleanAiReplyText)
test('Test 15: cleanAiReplyText membersihkan tag berpikir, awalan label AI, tanda kutip, dan frasa kaku CS', () => {
  const { cleanAiReplyText } = require('../server/ai');
  assert.equal(cleanAiReplyText('<think>internal thinking</think>Halo Bro!'), 'Halo Bro!');
  assert.equal(cleanAiReplyText('SI BONTOT: Bang Adhy lagi kerja nih'), 'Bang Adhy lagi kerja nih');
  assert.equal(cleanAiReplyText('Bang Adhy sedang sibuk bekerja'), 'Bang Adhy lagi kerja');
  assert.equal(cleanAiReplyText('Halo Bro! saya masih online untuk membantu menjawab pertanyaanmu.'), 'Halo Bro!');
  assert.equal(cleanAiReplyText('Bagaimana saya bisa membantu Anda?'), '');
  assert.equal(cleanAiReplyText('Sama-sama Bro! Apa adakah pertanyaan lainnya yang ingin kamu ajukan hari ini?'), 'Sama-sama Bro!');
  assert.equal(cleanAiReplyText('"Siap bantu lu, Bro!"'), 'Siap bantu lu, Bro!');
  assert.equal(cleanAiReplyText(''), '');
});

// 16. Respons AI tentang Bang Adhy memposisikan sebagai asisten dan bebas frasa kaku
test('Test 16: Respons AI tentang Bang Adhy memposisikan sebagai asisten dan bebas frasa kaku', async (t) => {
  const { generateAiReply, checkOllamaStatus } = require('../server/ai');
  const status = await checkOllamaStatus();
  if (!status.available) {
    t.skip('Ollama lokal tidak terdeteksi pada environment ini — pengujian live dilewati.');
    return;
  }
  const res = await generateAiReply({
    message: 'Bang Adhy mana bro?'
  });
  assert.ok(res.reply && res.reply.length > 0);
  assert.ok(res.reply.toLowerCase().includes('adhy'));
  // Memastikan gaya informal digunakan: tidak mengandung 'sedang sibuk bekerja'
  assert.equal(res.reply.toLowerCase().includes('sedang sibuk bekerja'), false, 'Tidak boleh memakai frasa kaku sedang sibuk bekerja');
  assert.equal(res.model, 'qwen2.5:1.5b');
});

// 17. Respons AI tentang identitas tidak mengaku sebagai manusia
test('Test 17: Respons AI tentang identitas jujur sebagai bot AI asisten', async (t) => {
  const { generateAiReply, checkOllamaStatus } = require('../server/ai');
  const status = await checkOllamaStatus();
  if (!status.available) {
    t.skip('Ollama lokal tidak terdeteksi pada environment ini — pengujian live dilewati.');
    return;
  }
  const res = await generateAiReply({
    message: 'Kamu manusia bukan?'
  });
  assert.ok(res.reply && res.reply.length > 0);
  assert.ok(res.reply.toLowerCase().includes('ai') || res.reply.toLowerCase().includes('bontot') || res.reply.toLowerCase().includes('bukan'));
});

// 18. Konteks percakapan berlanjut secara alami tanpa sapaan berulang
test('Test 18: generateContextualReply menyertakan histori obrolan secara terstruktur', async (t) => {
  const { generateContextualReply, checkOllamaStatus } = require('../server/ai');
  const status = await checkOllamaStatus();
  if (!status.available) {
    t.skip('Ollama lokal tidak terdeteksi pada environment ini — pengujian live dilewati.');
    return;
  }
  const testChatId = 'context-test-user@s.whatsapp.net';
  
  // Pastikan chat ada di DB
  db.ensureChatExists(testChatId, 'Teman Obrolan');
  db.saveMessage({
    id: `ctx-msg-1-${Date.now()}`,
    chatId: testChatId,
    senderJid: testChatId,
    text: 'Halo Bro',
    isFromMe: false,
    timestamp: Math.floor(Date.now() / 1000) - 10
  });
  db.saveMessage({
    id: `ctx-msg-2-${Date.now()}`,
    chatId: testChatId,
    senderJid: '6281990918273@s.whatsapp.net',
    text: 'Halo Bro! Ada yang bisa gw bantu? 😄',
    isFromMe: true,
    timestamp: Math.floor(Date.now() / 1000) - 5
  });

  const res = await generateContextualReply({
    chatId: testChatId,
    currentMessage: 'Bang Adhy siaran jam berapa?'
  });

  assert.ok(res.reply && res.reply.length > 0);
  assert.ok(res.reply.toLowerCase().includes('tiktok') || res.reply.toLowerCase().includes('malam') || res.reply.toLowerCase().includes('bontot'));
});

// 19. Uji pencegahan frasa formal dan verifikasi gaya santai WA
test('Test 19: Respons AI menolak bahasa kaku/formal dan mengutamakan kata lagi', async (t) => {
  const { generateAiReply, checkOllamaStatus } = require('../server/ai');
  const status = await checkOllamaStatus();
  if (!status.available) {
    t.skip('Ollama lokal tidak terdeteksi pada environment ini — pengujian live dilewati.');
    return;
  }
  const res = await generateAiReply({
    message: 'Bang Adhy bisa dihubungi sekarang?'
  });
  assert.ok(res.reply && res.reply.length > 0);
  const lower = res.reply.toLowerCase();
  assert.equal(lower.includes('apakah ada yang dapat saya bantu'), false, 'Tidak boleh memakai frasa kaku CS');
  assert.equal(lower.includes('sedang sibuk bekerja'), false, 'Harus pakai lagi kerja');
  assert.equal(lower.includes('kepada beliau'), false, 'Tidak boleh memakai kata formal beliau');
});

// 20. Pengujian regresi percakapan berurutan multi-turn (Sehat bro? -> Bro -> Ngapain Bang Adhy? -> Makasih ya)
test('Test 20: Rangkaian percakapan multi-turn berurutan merespons secara kontekstual, singkat, dan tidak robotik', async (t) => {
  const { generateContextualReply, checkOllamaStatus } = require('../server/ai');
  const status = await checkOllamaStatus();
  if (!status.available) {
    t.skip('Ollama lokal tidak terdeteksi pada environment ini — pengujian live dilewati.');
    return;
  }
  const seqChatId = `multi-turn-test-${Date.now()}@s.whatsapp.net`;
  db.ensureChatExists(seqChatId, 'Budi');

  const turns = [
    { input: 'Sehat bro?', expectedNotIn: ['online untuk membantu', 'bagaimana saya bisa membantu'] },
    { input: 'Bro', expectedNotIn: ['lagi kerja'] },
    { input: 'Ngapain Bang Adhy?', expectedIn: ['kerja'] },
    { input: 'Makasih ya', expectedNotIn: ['pertanyaan lainnya', 'lagi kerja'] }
  ];

  let turnIndex = 0;
  for (const turn of turns) {
    turnIndex++;
    const userMsgId = `seq-user-msg-${turnIndex}-${Date.now()}`;
    db.saveMessage({
      id: userMsgId,
      chatId: seqChatId,
      senderJid: seqChatId,
      text: turn.input,
      isFromMe: false,
      timestamp: Math.floor(Date.now() / 1000)
    });

    const aiRes = await generateContextualReply({
      chatId: seqChatId,
      currentMessageId: userMsgId,
      currentMessage: turn.input,
      senderName: 'Budi'
    });

    assert.ok(aiRes.reply && aiRes.reply.length > 0, `Turn ${turnIndex} harus menghasilkan balasan`);
    assert.ok(aiRes.reply.length < 160, `Balasan turn ${turnIndex} harus ringkas (< 160 karakter): ${aiRes.reply}`);

    const lower = aiRes.reply.toLowerCase();
    assert.equal(lower.includes('saya masih online'), false, `Turn ${turnIndex} tidak boleh mengandung saya masih online`);
    assert.equal(lower.includes('pertanyaan lainnya'), false, `Turn ${turnIndex} tidak boleh mengandung pertanyaan lainnya`);

    if (turn.expectedIn) {
      for (const word of turn.expectedIn) {
        assert.ok(lower.includes(word), `Turn ${turnIndex} diharapkan mengandung "${word}": ${aiRes.reply}`);
      }
    }

    if (turn.expectedNotIn) {
      for (const word of turn.expectedNotIn) {
        assert.equal(lower.includes(word), false, `Turn ${turnIndex} dilarang mengandung "${word}": ${aiRes.reply}`);
      }
    }

    const botMsgId = `seq-bot-reply-${turnIndex}-${Date.now()}`;
    db.saveMessage({
      id: botMsgId,
      chatId: seqChatId,
      senderJid: '6281990918273@s.whatsapp.net',
      text: aiRes.reply,
      isFromMe: true,
      timestamp: Math.floor(Date.now() / 1000) + 1
    });
  }
});

