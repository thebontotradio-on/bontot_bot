const axios = require('axios');
const db = require('./db');

const OLLAMA_HOST = process.env.OLLAMA_HOST || 'http://127.0.0.1:11434';
const DEFAULT_SYSTEM_PROMPT =
  'Kamu adalah SI BONTOT, asisten WhatsApp milik THE BONTOT RADIO. Kamu ramah, santai, cerdas, humoris seperlunya, dan berbicara dalam bahasa Indonesia sehari-hari. Jawab seperti percakapan WhatsApp yang alami, singkat jika pertanyaannya sederhana, dan lebih terperinci jika diperlukan. Pahami konteks percakapan sebelum menjawab. Jangan mengarang informasi yang tidak kamu ketahui. Jangan mengulang salam atau jawaban yang sama secara tidak perlu. Jangan menyebut dirimu sebagai manusia. Jika pertanyaan tidak jelas, tanyakan dengan sopan.';

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
        stream: false
      },
      {
        timeout: 45000
      }
    );

    const replyContent = response.data?.message?.content;
    if (!replyContent || replyContent.trim().length === 0) {
      throw new Error('Ollama tidak memberikan balasan teks.');
    }

    return {
      reply: replyContent.trim(),
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
async function generateContextualReply({ chatId, currentMessage, systemPrompt }) {
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

  // Exclude current message if already stored at the tail of history
  const recentHistory = history.filter(
    (h) => h.text && h.text.trim().length > 0 && !(h.text === currentMessage && !h.is_from_me)
  );

  for (const h of recentHistory) {
    messagesPayload.push({
      role: h.is_from_me ? 'assistant' : 'user',
      content: h.text.trim()
    });
  }

  // Append current message as the latest prompt
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
        stream: false
      },
      {
        timeout: 30000
      }
    );

    const replyContent = response.data?.message?.content;
    if (!replyContent || typeof replyContent !== 'string' || replyContent.trim().length === 0) {
      throw new Error('Respons AI kosong.');
    }

    return {
      reply: replyContent.trim(),
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
  generateAiReply,
  generateContextualReply,
  DEFAULT_SYSTEM_PROMPT
};
