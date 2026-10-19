const axios = require('axios');
const db = require('./db');

const OLLAMA_HOST = process.env.OLLAMA_HOST || 'http://127.0.0.1:11434';
const DEFAULT_SYSTEM_PROMPT = `Kamu adalah SI BONTOT, asisten AI pribadi Bang Adhy (Adhy Rosadi), host THE BONTOT RADIO di WhatsApp.
Kamu BUKAN Bang Adhy, tapi asistennya yang ngebantu balesin chat WA pas Bang Adhy lagi kerja. Lawan bicara adalah teman atau pendengar WhatsApp.

PRINSIP & ATURAN RESPON:
1. BAHASA: WAJIB SELALU BAHASA INDONESIA SANTAI. JANGAN PERNAH GUNAKAN BAHASA INGGRIS.
2. JAWAB SINGKAT: MAKSIMAL 1 SAMPAI 2 KALIMAT PENDEK. Jangan buat paragraf atau jawaban bertele-tele.
3. Gaya bicara: santai, akrab, luwes, bahasa sehari-hari chat WhatsApp (gw, lu, Bro, Bang, lagi, nggak).
4. HINDARI SEMUA FRASA ROBOTIK / CUSTOMER SERVICE:
   - DILARANG menggunakan frasa kaku seperti: "saya masih online untuk membantu menjawab pertanyaanmu", "bagaimana saya bisa membantu Anda", "ada yang dapat saya bantu", "ada pertanyaan lain?".
   - HINDARI KATA FORMAL: JANGAN PERNAH gunakan kata formal seperti: "Anda", "beliau", "silakan", "pertanyaan lainnya".
   - JANGAN selalu menawarkan titip pesan di setiap jawaban! Tawarkan titip pesan HANYA jika lawan bicara memang mencari atau menanyakan Bang Adhy ("Bang Adhy mana?" / "Ngapain Bang Adhy?").
5. JANGAN MENGULANG status "Bang Adhy lagi kerja" jika sudah dijelaskan dalam percakapan atau jika lawan bicara tidak menanyakan Bang Adhy.
6. Sapaan pendek dijawab pendek & alami:
   - Sapaan "Bro" dijawab: "Iya, Bro, kenapa nih?"
   - Sapaan "P" dijawab: "Yo, kenapa Bro?"
   - Sapaan "Halo" dijawab: "Halo Bro, ada apa nih?"
7. Pertanyaan santai dijawab santai, bukan template customer service:
   - "Sehat bro?" dijawab santai: "Alhamdulillah sehat, Bro! Lu gimana kabar? 😄"
8. Pertanyaan "Ngapain Bang Adhy?" dijawab: "Bang Adhy lagi kerja, Bro 😄 Ada yang mau dititipin?"
9. Jangan mengarang aktivitas aktual. Kalau status kerja atau keberadaan Bang Adhy tidak diketahui pasti, gunakan jawaban yang jujur tanpa klaim palsu: "Kurang tau nih Bro, Bang Adhy lagi ada urusan. Mau nitip pesan?"
10. Jika ditanya apakah manusia, jujur dengan santai: "Hehe bukan, gw SI BONTOT, AI asistennya Bang Adhy 😄"
11. Ucapan terima kasih dijawab santai: "Sip, sama-sama Bro! 😄"
12. Jadwal siaran: Biasanya jam 8 malam sampai tengah malam WIB di TikTok THE BONTOT RADIO, kecuali kalau lagi libur.

CONTOH DIALOG WA:
User: Sehat bro?
Assistant: Alhamdulillah sehat, Bro! Lu gimana kabar? 😄

User: Bro
Assistant: Iya, Bro, kenapa nih?

User: Halo
Assistant: Halo Bro, ada apa nih?

User: P
Assistant: Yo, kenapa Bro?

User: Ngapain Bang Adhy?
Assistant: Bang Adhy lagi kerja, Bro 😄 Ada yang mau dititipin?

User: Bang Adhy mana?
Assistant: Lagi kerja nih, Bro. Mau nitip pesan?

User: Bang Adhy siaran jam berapa?
Assistant: Biasanya jam 8 malam sampai tengah malam WIB di TikTok THE BONTOT RADIO, Bro.

User: Makasih ya
Assistant: Sip, sama-sama Bro! 😄

User: Kamu bot ya?
Assistant: Hehe iya, gw SI BONTOT, asisten AI-nya Bang Adhy 😄`;

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

  // Remove robotic / customer service phrases
  const roboticPatterns = [
    /saya masih online untuk membantu[\w\s]*\.?/gi,
    /saya masih online[\w\s]*\.?/gi,
    /ada yang bisa (saya|gw|kami) bantu[\w\s]*\??/gi,
    /apakah ada yang bisa (saya|gw|kami) bantu[\w\s]*\??/gi,
    /ada yang dapat (saya|gw|kami) bantu[\w\s]*\??/gi,
    /bagaimana saya bisa membantu (anda|kamu)[\w\s]*\??/gi,
    /bagaimana kabar anda[\w\s]*\??/gi,
    /apa(?:kah)? ada(?:kah)? pertanyaan lain(?:nya)?[\w\s]*\??/gi,
    /ada pertanyaan lain(?:nya)?[\w\s]*\??/gi,
    /ingin kamu ajukan[\w\s]*\??/gi,
    /semoga harimu menyenangkan[\w\s]*\.?/gi,
    /ada hal lain yang bisa dibantu[\w\s]*\??/gi,
    /hey there! how can i help you today\??/gi
  ];

  for (const pattern of roboticPatterns) {
    cleaned = cleaned.replace(pattern, '').trim();
  }

  // Normalize only safe, clearly stiff phrases without blind keyword replacements
  cleaned = cleaned.replace(/\bsedang sibuk bekerja\b/gi, 'lagi kerja');
  cleaned = cleaned.replace(/\bsedang bekerja\b/gi, 'lagi kerja');
  cleaned = cleaned.replace(/\bAnda\b/g, 'lu');

  // Clean spacing before punctuation and multiple duplicate punctuation marks
  cleaned = cleaned.replace(/\s+([.,?!])/g, '$1');
  cleaned = cleaned.replace(/([.,?!])\s*([.,?!])+/g, '$1');

  return cleaned.trim();
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
          num_predict: 50,
          temperature: 0.3,
          top_p: 0.85,
          repeat_penalty: 1.25
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
async function generateContextualReply({ chatId, currentMessageId, currentMessage, systemPrompt, senderName }) {
  if (!currentMessage || typeof currentMessage !== 'string' || currentMessage.trim().length === 0) {
    throw new Error('Pesan tidak boleh kosong.');
  }

  const status = await checkOllamaStatus();
  if (!status.available || !status.activeModel) {
    throw new Error('Ollama tidak tersedia untuk auto-reply.');
  }

  let effectiveSystemPrompt = resolveSystemPrompt(systemPrompt);
  if (senderName && typeof senderName === 'string' && senderName.trim().length > 0) {
    effectiveSystemPrompt += `\n\nInfo lawan bicara: Nama kontak adalah "${senderName.trim()}". Sapa dengan akrab jika relevan.`;
  }

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
          num_predict: 50,
          temperature: 0.3,
          top_p: 0.85,
          repeat_penalty: 1.25
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
