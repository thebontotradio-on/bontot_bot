const axios = require('axios');
const db = require('./db');

const OLLAMA_HOST = process.env.OLLAMA_HOST || 'http://127.0.0.1:11434';
const DEFAULT_SYSTEM_PROMPT = `Kamu adalah SI BONTOT, asisten AI Bang Adhy (Adhy Rosadi), host THE BONTOT RADIO.
Kamu BUKAN Bang Adhy, tapi asistennya yang ngebantu balesin chat WA pas Bang Adhy lagi kerja. Lawan bicara adalah teman atau pendengar WhatsApp.

ATURAN BAHASA WA SEHARI-HARI (PENTING):
1. Pakai bahasa chat WA sehari-hari yang santai, akrab, hangat, dan luwes.
2. Utamakan kata "lagi", JANGAN pakai "sedang". Gunakan "Bang Adhy lagi kerja", bukan "sedang sibuk bekerja".
3. Gunakan "Mau nitip pesan buat Bang Adhy, Bro?", BUKAN kalimat kaku customer service.
4. HINDARI KATA FORMAL:
   - JANGAN pakai kata "beliau" (sebut saja "Bang Adhy").
   - JANGAN pakai "Anda" (pakai "lu" atau sapa "Bro", "Bang", "Kak").
   - JANGAN pakai "silakan", "bagaimana kabar Anda", "dapat membantu Anda".
5. Gunakan kata "gw", "lu", "Bro", "Bang", "lagi", "nggak / enggak", "nih", "ya" secara wajar sesuai konteks.
6. Respons harus ringkas, hangat, spontan, dan tidak terdengar seperti customer service. Jangan selalu mengulang sapaan atau menawarkan bantuan di akhir setiap jawaban.
7. Jika ditanya "Bang Adhy mana?": Jawab singkat dan santai, contoh: "Bang Adhy lagi kerja, Bro 😄 Mau nitip pesan?"
8. Jangan mengarang aktivitas aktual. Kalau status kerja atau keberadaan Bang Adhy tidak diketahui pasti, gunakan jawaban yang jujur dan santai: "Kurang tau nih Bro, Bang Adhy lagi ada urusan. Mau nitip pesan?"
9. Jika ditanya apakah manusia, jujur dengan santai: "Hehe bukan, gw SI BONTOT, AI asistennya Bang Adhy 😄"
10. Jadwal siaran: Biasanya jam 8 malam sampai tengah malam WIB di TikTok THE BONTOT RADIO, kecuali kalau lagi libur.

CONTOH GAYA CHAT WA:
User: Bang Adhy mana bro?
Assistant: Bang Adhy lagi kerja, Bro 😄 Mau nitip pesan?

User: Apa kabar?
Assistant: Baik nih, Bro! Lu gimana kabar? 😄

User: Kamu manusia bukan?
Assistant: Hehe bukan, gw SI BONTOT, AI asistennya Bang Adhy 😄

User: Bang Adhy siaran jam berapa?
Assistant: Biasanya jam 8 malam sampai tengah malam WIB di TikTok THE BONTOT RADIO, Bro. Pantengin aja ya!

User: Bang Adhy lagi di mana sekarang?
Assistant: Kurang tau nih Bro, Bang Adhy lagi ada urusan. Mau nitip pesan?`;

/**
 * Sanitizes and cleans raw AI output so no internal tags or prefixes leak into WhatsApp messages
 */
function cleanAiReplyText(text) {
  if (!text || typeof text !== 'string') return '';
  let cleaned = text.trim();

  // Strip accidental thinking tags <think>...</think>
  cleaned = cleaned.replace(/<think>[\s\S]*?<\/think>/gi, '').trim();

  // Strip accidental prefixes like "AI:", "SI BONTOT:", "Assistant:", "Bot:"
  cleaned = cleaned.replace(/^(SI\s*BONTOT|AI|Assistant|Bot)\s*:\s*/i, '').trim();

  // Strip surrounding quotes if whole string is wrapped
  if ((cleaned.startsWith('"') && cleaned.endsWith('"')) || (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
    cleaned = cleaned.slice(1, -1).trim();
  }

  // Soft conversational normalization (replace overly stiff corporate/formal phrases)
  cleaned = cleaned.replace(/bagaimana kabar Anda\??/gi, 'lu gimana kabar?');
  cleaned = cleaned.replace(/ada yang dapat (saya|gw) bantu\??/gi, 'mau nitip pesan?');
  cleaned = cleaned.replace(/sedang sibuk bekerja/gi, 'lagi kerja');
  cleaned = cleaned.replace(/sedang bekerja/gi, 'lagi kerja');
  cleaned = cleaned.replace(/buat beliau/gi, 'buat Bang Adhy');
  cleaned = cleaned.replace(/untuk beliau/gi, 'buat Bang Adhy');
  cleaned = cleaned.replace(/ke beliau/gi, 'ke Bang Adhy');
  cleaned = cleaned.replace(/\bbeliau\b/gi, 'Bang Adhy');
  cleaned = cleaned.replace(/\bAnda\b/gi, 'lu');

  return cleaned;
}

/**
 * Check Ollama service availability and installed models
 */
async function checkOllamaStatus() {
  try {
    const response = await axios.get(`${OLLAMA_HOST}/api/tags`, {
      timeout: 2500
    });

    const models = (response.data && response.data.models) || [];
    const modelNames = models.map(m => m.name);

    return {
      available: true,
      host: OLLAMA_HOST,
      models: modelNames,
      activeModel: modelNames.length > 0 ? (process.env.OLLAMA_MODEL || modelNames[0]) : null,
      message: modelNames.length > 0
        ? `Ollama aktif dengan ${modelNames.length} model terpasang.`
        : 'Ollama aktif, tetapi belum ada model yang diunduh (jalankan: ollama run qwen2.5:1.5b).'
    };
  } catch (err) {
    return {
      available: false,
      host: OLLAMA_HOST,
      models: [],
      activeModel: null,
      message: 'Ollama belum aktif di ' + OLLAMA_HOST + '. Pastikan aplikasi Ollama sudah dijalankan.'
    };
  }
}

/**
 * Resolve effective system prompt based on precedence:
 * 1. Request systemPrompt if non-empty
 * 2. Saved system prompt in DB
 * 3. Default: SI BONTOT persona prompt
 */
function resolveSystemPrompt(requestPrompt) {
  if (typeof requestPrompt === 'string' && requestPrompt.trim().length > 0) {
    return requestPrompt.trim();
  }

  const savedPrompt = db.getSetting('ai_system_prompt');
  if (savedPrompt && savedPrompt.trim().length > 0) {
    return savedPrompt.trim();
  }

  return DEFAULT_SYSTEM_PROMPT;
}

/**
 * Generate AI reply draft using local Ollama.
 * Never sends WhatsApp credentials.
 * Never sends WhatsApp messages automatically.
 */
async function generateAiReply({ message, systemPrompt }) {
  if (!message || typeof message !== 'string' || message.trim().length === 0) {
    throw new Error('Pesan input tidak boleh kosong.');
  }

  const status = await checkOllamaStatus();
  if (!status.available) {
    throw new Error('Ollama lokal tidak terdeteksi. Silakan jalankan Ollama terlebih dahulu.');
  }

  if (!status.activeModel) {
    throw new Error('Belum ada model AI yang terpasang di Ollama. Unduh model ringan dengan: ollama run qwen2.5:1.5b');
  }

  const effectiveSystemPrompt = resolveSystemPrompt(systemPrompt);

  try {
    const response = await axios.post(
      `${OLLAMA_HOST}/api/chat`,
      {
        model: status.activeModel,
        messages: [
          { role: 'system', content: effectiveSystemPrompt },
          { role: 'user', content: message.trim() }
        ],
        options: {
          temperature: 0.6,
          top_p: 0.9,
          repeat_penalty: 1.15
        },
        stream: false
      },
      {
        timeout: 90000
      }
    );

    const rawReply = response.data?.message?.content;
    const cleaned = cleanAiReplyText(rawReply);
    if (!cleaned || cleaned.length === 0) {
      throw new Error('Ollama tidak memberikan balasan teks.');
    }

    return {
      reply: cleaned,
      model: status.activeModel,
      usedSystemPrompt: effectiveSystemPrompt
    };
  } catch (err) {
    if (err.code === 'ECONNREFUSED') {
      throw new Error('Koneksi ke Ollama terputus saat memproses balasan.');
    }
    if (err.code === 'ETIMEDOUT' || err.message?.includes('timeout')) {
      throw new Error('Ollama memerlukan waktu terlalu lama untuk merespons (timeout).');
    }
    throw new Error(err.response?.data?.error || err.message || 'Gagal menghasilkan balasan AI.');
  }
}

/**
 * Generate contextual auto-reply for SI BONTOT including recent chat thread history.
 * Never sends credentials or auth tokens to Ollama.
 */
async function generateContextualReply({ chatId, currentMessageId, currentMessage, systemPrompt }) {
  if (!currentMessage || typeof currentMessage !== 'string' || currentMessage.trim().length === 0) {
    throw new Error('Pesan tidak boleh kosong.');
  }

  const status = await checkOllamaStatus();
  if (!status.available || !status.activeModel) {
    throw new Error('Ollama tidak tersedia untuk auto-reply.');
  }

  const effectiveSystemPrompt = resolveSystemPrompt(systemPrompt);

  // Retrieve recent context from chat history (up to 5 recent messages)
  const history = chatId ? db.getRecentMessagesForContext(chatId, 5) : [];
  const messagesPayload = [
    { role: 'system', content: effectiveSystemPrompt }
  ];

  // Exclude current message if already stored in history
  const recentHistory = history.filter((h) => {
    if (!h.text || h.text.trim().length === 0) return false;
    if (currentMessageId && h.id === currentMessageId) return false;
    if (!currentMessageId && h.text === currentMessage && !h.is_from_me) return false;
    return true;
  });

  for (const h of recentHistory) {
    messagesPayload.push({
      role: h.is_from_me ? 'assistant' : 'user',
      content: h.text.trim()
    });
  }

  // Append current message as the latest user prompt
  messagesPayload.push({
    role: 'user',
    content: currentMessage.trim()
  });

  try {
    const response = await axios.post(
      `${OLLAMA_HOST}/api/chat`,
      {
        model: status.activeModel,
        messages: messagesPayload,
        options: {
          temperature: 0.6,
          top_p: 0.9,
          repeat_penalty: 1.15
        },
        stream: false
      },
      {
        timeout: 90000
      }
    );

    const rawReply = response.data?.message?.content;
    const cleaned = cleanAiReplyText(rawReply);
    if (!cleaned || cleaned.length === 0) {
      throw new Error('Respons AI kosong.');
    }

    return {
      reply: cleaned,
      model: status.activeModel
    };
  } catch (err) {
    if (err.code === 'ECONNREFUSED') {
      throw new Error('Koneksi ke Ollama terputus.');
    }
    if (err.code === 'ETIMEDOUT' || err.message?.includes('timeout')) {
      throw new Error('Ollama timeout.');
    }
    throw new Error(err.response?.data?.error || err.message || 'Gagal memproses auto-reply.');
  }
}

module.exports = {
  checkOllamaStatus,
  resolveSystemPrompt,
  cleanAiReplyText,
  generateAiReply,
  generateContextualReply,
  DEFAULT_SYSTEM_PROMPT
};
