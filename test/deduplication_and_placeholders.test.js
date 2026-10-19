const test = require('node:test');
const assert = require('node:assert/strict');
const { MessageDeduplicator, replacePlaceholders, formatJidDisplay } = require('../server/utils');

test('MessageDeduplicator: should detect duplicate messages and allow unique ones', () => {
  const deduplicator = new MessageDeduplicator(5);

  assert.equal(deduplicator.isDuplicate('msg-1'), false, 'First occurrence should not be duplicate');
  assert.equal(deduplicator.isDuplicate('msg-2'), false, 'Different ID should not be duplicate');
  assert.equal(deduplicator.isDuplicate('msg-1'), true, 'Second occurrence of msg-1 must be duplicate');
  assert.equal(deduplicator.isDuplicate('msg-2'), true, 'Second occurrence of msg-2 must be duplicate');
  assert.equal(deduplicator.has('msg-1'), true, 'Should confirm msg-1 exists');
  assert.equal(deduplicator.has('msg-3'), false, 'Should confirm msg-3 does not exist');
});

test('MessageDeduplicator: should evict oldest items when exceeding maxSize', () => {
  const deduplicator = new MessageDeduplicator(3);

  deduplicator.isDuplicate('id-1');
  deduplicator.isDuplicate('id-2');
  deduplicator.isDuplicate('id-3');
  assert.equal(deduplicator.size(), 3);

  // Add 4th item, id-1 should be evicted
  deduplicator.isDuplicate('id-4');
  assert.equal(deduplicator.has('id-1'), false, 'id-1 should have been evicted');
  assert.equal(deduplicator.has('id-2'), true);
  assert.equal(deduplicator.has('id-3'), true);
  assert.equal(deduplicator.has('id-4'), true);
});

test('MessageDeduplicator: should handle invalid or non-string inputs safely', () => {
  const deduplicator = new MessageDeduplicator();
  assert.equal(deduplicator.isDuplicate(null), false);
  assert.equal(deduplicator.isDuplicate(undefined), false);
  assert.equal(deduplicator.isDuplicate(12345), false);
});

test('replacePlaceholders: should replace template variables correctly', () => {
  const template = 'Halo {{name}}, konfirmasi pesanan #{{order_id}} sebesar Rp{{amount}}.';
  const data = {
    name: 'Budi Santoso',
    order_id: 'WB-9901',
    amount: '150.000'
  };

  const result = replacePlaceholders(template, data);
  assert.equal(result, 'Halo Budi Santoso, konfirmasi pesanan #WB-9901 sebesar Rp150.000.');
});

test('replacePlaceholders: should preserve unmapped placeholders or handle empty data', () => {
  const template = 'Halo {{name}}, kode OTP Anda adalah {{otp}}. Tanggal: {{date}}';
  const data = {
    name: 'Siti'
  };

  const result = replacePlaceholders(template, data);
  assert.equal(result, 'Halo Siti, kode OTP Anda adalah {{otp}}. Tanggal: {{date}}');
});

test('replacePlaceholders: should handle edge cases safely', () => {
  assert.equal(replacePlaceholders(null), '');
  assert.equal(replacePlaceholders(undefined), '');
  assert.equal(replacePlaceholders('Teks biasa tanpa kurung'), 'Teks biasa tanpa kurung');
});

test('formatJidDisplay: should handle @lid, @g.us, and @s.whatsapp.net correctly without fake numbers', () => {
  // @lid should NOT be converted to phone number
  const lidResult = formatJidDisplay('12345678901234@lid');
  assert.equal(lidResult.includes('Pengguna (123456...)'), true);

  // pushName takes precedence
  const withPushName = formatJidDisplay('12345678901234@lid', 'Pak Budi');
  assert.equal(withPushName, 'Pak Budi');

  // group chat
  const groupResult = formatJidDisplay('12036302@g.us');
  assert.equal(groupResult, 'Grup WhatsApp');

  // regular phone
  const phoneResult = formatJidDisplay('628123456789@s.whatsapp.net');
  assert.equal(phoneResult, '+628123456789');
});
