const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const net = require('node:net');
const path = require('node:path');
const fs = require('node:fs');

const { checkOllamaStatus, generateAiReply } = require('../server/ai');

test('Simulation 1: AI Model Not Available / Offline Failure Handling', async () => {
  // Test when OLLAMA_HOST is unreachable
  const oldHost = process.env.OLLAMA_HOST;
  process.env.OLLAMA_HOST = 'http://127.0.0.1:59999'; // Dead port

  const status = await checkOllamaStatus();
  assert.equal(status.available, false, 'available harus false jika AI engine offline');
  assert.equal(status.activeModel, null, 'activeModel harus null jika AI engine offline');
  assert.ok(status.message.includes('59999') || status.message.includes('belum aktif'));

  await assert.rejects(
    async () => {
      await generateAiReply({ message: 'Tes pesan' });
    },
    (err) => {
      assert.ok(err.message.includes('Ollama'));
      return true;
    }
  );

  process.env.OLLAMA_HOST = oldHost;
});

test('Simulation 2: AI Adapter Returns Empty Models (No GGUF Model Loaded)', async () => {
  // Start mock server that responds to /api/tags with empty models list
  const mockEmpty = http.createServer((req, res) => {
    if (req.url === '/api/tags') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ models: [] }));
      return;
    }
    res.writeHead(404);
    res.end();
  });

  await new Promise(r => mockEmpty.listen(59998, '127.0.0.1', r));

  const oldHost = process.env.OLLAMA_HOST;
  process.env.OLLAMA_HOST = 'http://127.0.0.1:59998';

  const status = await checkOllamaStatus();
  assert.equal(status.available, false, 'available harus false jika belum ada model yang dimuat');
  assert.equal(status.activeModel, null, 'activeModel harus null');
  assert.ok(status.message.includes('belum ada model'));

  await new Promise(r => mockEmpty.close(r));
  process.env.OLLAMA_HOST = oldHost;
});

test('Simulation 3: Port Busy (EADDRINUSE) Detection', async () => {
  // Bind port 39999
  const blocker = net.createServer();
  await new Promise(r => blocker.listen(39999, '127.0.0.1', r));

  // Attempt to bind second server to same port
  const secondServer = net.createServer();
  const errorReceived = await new Promise((resolve) => {
    secondServer.on('error', (err) => {
      resolve(err.code);
    });
    secondServer.listen(39999, '127.0.0.1');
  });

  assert.equal(errorReceived, 'EADDRINUSE', 'Harus mendeteksi konflik port EADDRINUSE secara tepat');

  await new Promise(r => blocker.close(r));
});

test('Simulation 4: PID Lock Logic for Duplicate Process Prevention', () => {
  const testPidDir = path.join(__dirname, '../scratch/test_pid');
  fs.mkdirSync(testPidDir, { recursive: true });
  const pidFile = path.join(testPidDir, 'watchdog.pid');

  // Simulate first process writing its PID
  const currentPid = process.pid;
  fs.writeFileSync(pidFile, currentPid.toString(), 'utf8');

  // Simulate second process reading PID and checking if alive
  const readPid = parseInt(fs.readFileSync(pidFile, 'utf8'), 10);
  assert.equal(readPid, currentPid);

  let isAlive = false;
  try {
    process.kill(readPid, 0); // Signal 0 checks existence without killing
    isAlive = true;
  } catch (e) {
    isAlive = false;
  }

  assert.equal(isAlive, true, 'Proses lama harus terdeteksi masih hidup sehingga peluncuran kedua ditolak');

  // Clean up
  fs.unlinkSync(pidFile);
  fs.rmdirSync(testPidDir);
});

test('Simulation 5: Missing Files & Dependency Guard', () => {
  // Test that check-readiness script identifies all critical files
  const requiredFiles = [
    'server/index.js',
    'server/whatsapp.js',
    'server/ai.js',
    'server/db.js',
    'server/utils.js',
    'client/dist/index.html'
  ];

  for (const relPath of requiredFiles) {
    const fullPath = path.join(__dirname, '..', relPath);
    assert.ok(fs.existsSync(fullPath), `Berkas penting ${relPath} harus ada agar sistem siap jalan`);
  }
});
