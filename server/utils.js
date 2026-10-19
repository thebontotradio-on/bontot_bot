/**
 * Helper utilities for WA BONTOT
 */

/**
 * Replace placeholders in a text template.
 * Example: replacePlaceholders("Halo {{name}}, jam {{time}}", { name: "Budi", time: "10:00" })
 * => "Halo Budi, jam 10:00"
 */
function replacePlaceholders(template, data = {}) {
  if (typeof template !== 'string') return '';
  return template.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (match, key) => {
    return Object.prototype.hasOwnProperty.call(data, key) && data[key] !== null && data[key] !== undefined
      ? String(data[key])
      : match;
  });
}

/**
 * Builds a stable message deduplication key considering remote JID, message ID,
 * participant (for group chats), and fromMe flag.
 * Prevents ID collisions across different chats or participants.
 */
function buildMessageDeduplicationKey(chatId, messageId, participant = '', fromMe = false) {
  if (!chatId || !messageId) return messageId || '';
  const senderPart = fromMe ? 'me' : (participant || 'direct');
  return `${chatId}:${senderPart}:${messageId}`;
}

/**
 * Check if a name is a generic fallback or raw identifier instead of a real contact name.
 */
function isFallbackOrGenericName(name, jid = '') {
  if (!name || typeof name !== 'string') return true;
  const trimmed = name.trim();
  if (trimmed.length === 0) return true;
  if (jid && trimmed === jid) return true;
  if (jid && trimmed === jid.split('@')[0]) return true;
  if (/^Pengguna\s*\(/i.test(trimmed)) return true;
  if (/^User\s*\(/i.test(trimmed)) return true;
  if (trimmed === 'Unknown' || trimmed === 'Grup WhatsApp') return true;
  return false;
}

/**
 * Deduplicator for WhatsApp messages to prevent processing or emitting duplicate messages.
 * Stores recent message keys and raw IDs with TTL / max size.
 */
class MessageDeduplicator {
  constructor(maxSize = 2000) {
    this.maxSize = maxSize;
    this.seenIds = new Set();
    this.idQueue = [];
  }

  /**
   * Checks if an ID or key has been seen. If not seen, records it and returns false.
   * If already seen, returns true (is duplicate).
   * @param {string} id - Unique message ID or composite key
   * @returns {boolean} true if duplicate, false if new
   */
  isDuplicate(id) {
    if (!id || typeof id !== 'string') return false;

    if (this.seenIds.has(id)) {
      return true;
    }

    this.seenIds.add(id);
    this.idQueue.push(id);

    // Evict oldest if exceeding capacity
    if (this.idQueue.length > this.maxSize) {
      const oldestId = this.idQueue.shift();
      this.seenIds.delete(oldestId);
    }

    return false;
  }

  /**
   * Explicitly add an ID to the seen set.
   */
  add(id) {
    if (!id || typeof id !== 'string') return;
    if (!this.seenIds.has(id)) {
      this.seenIds.add(id);
      this.idQueue.push(id);
      if (this.idQueue.length > this.maxSize) {
        const oldestId = this.idQueue.shift();
        this.seenIds.delete(oldestId);
      }
    }
  }

  /**
   * Explicitly check if an ID exists without adding it.
   */
  has(id) {
    if (!id || typeof id !== 'string') return false;
    return this.seenIds.has(id);
  }

  /**
   * Clear all tracked IDs.
   */
  clear() {
    this.seenIds.clear();
    this.idQueue = [];
  }

  size() {
    return this.seenIds.size;
  }
}

/**
 * Format JID safely without mangling @lid or turning it into fake phone numbers.
 * Requirement:
 * "Jangan mengubah JID @lid menjadi nomor telepon palsu.
 *  Jangan memproses ulang alamat yang sudah mengandung @.
 *  Jangan menampilkan JID internal sebagai nomor kontak biasa."
 */
function formatJidDisplay(jid, pushName = '') {
  if (!jid || typeof jid !== 'string') return 'Unknown';
  if (pushName && typeof pushName === 'string' && pushName.trim().length > 0 && !isFallbackOrGenericName(pushName)) {
    return pushName.trim();
  }

  // If already contains @lid
  if (jid.endsWith('@lid')) {
    const rawId = jid.split('@')[0];
    return `Pengguna (${rawId.slice(0, 6)}...)`;
  }

  // If group chat
  if (jid.endsWith('@g.us')) {
    return 'Grup WhatsApp';
  }

  // Standard user @s.whatsapp.net
  if (jid.endsWith('@s.whatsapp.net')) {
    const phone = jid.split('@')[0];
    return `+${phone}`;
  }

  return jid;
}

module.exports = {
  replacePlaceholders,
  buildMessageDeduplicationKey,
  isFallbackOrGenericName,
  MessageDeduplicator,
  formatJidDisplay
};
