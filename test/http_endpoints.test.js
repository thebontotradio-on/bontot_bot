const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');

// We can test express routing directly or test endpoints against a test server
const db = require('../server/db');
const { checkOllamaStatus, resolveSystemPrompt, generateAiReply } = require('../server/ai');
const waManager = require('../server/whatsapp');

test('AI service: should check Ollama status and handle replies gracefully', async () => {
  const status = await checkOllamaStatus();
  assert.equal(typeof status.available, 'boolean');
  if (status.available) {
    assert.ok(status.activeModel);
    const replyRes = await generateAiReply({ message: 'Halo tes' });
    assert.ok(replyRes.reply);
  } else {
    assert.equal(status.activeModel, null);
    await assert.rejects(
      async () => {
        await generateAiReply({ message: 'Halo' });
      },
      (err) => {
        assert.ok(err.message.includes('Ollama'));
        return true;
      }
    );
  }
});

test('WhatsApp manager: status and contracts', () => {
  const status = waManager.getStatus();
  assert.ok(status.status);
  assert.equal(['connecting', 'qr', 'connected', 'closed'].includes(status.status), true);

  const qrData = waManager.getQR();
  assert.ok(qrData);
  assert.equal(typeof qrData.status, 'string');
});

test('WhatsApp manager: safe destination formatting', () => {
  // Respect @lid
  const lid = waManager.formatDestinationJid('12345678901234@lid');
  assert.equal(lid, '12345678901234@lid');

  // Respect @g.us
  const group = waManager.formatDestinationJid('12036302@g.us');
  assert.equal(group, '12036302@g.us');

  // Convert 0812... to 62812...@s.whatsapp.net
  const phone = waManager.formatDestinationJid('08123456789');
  assert.equal(phone, '628123456789@s.whatsapp.net');

  // Preserve existing @s.whatsapp.net
  const existing = waManager.formatDestinationJid('628123456789@s.whatsapp.net');
  assert.equal(existing, '628123456789@s.whatsapp.net');
});

test('WhatsApp manager: sendMessage rejects when disconnected', async () => {
  await assert.rejects(
    async () => {
      await waManager.sendMessage('08123456789', 'Tes pesan');
    },
    (err) => {
      assert.ok(err.message.includes('WhatsApp belum terhubung'));
      return true;
    }
  );
});
