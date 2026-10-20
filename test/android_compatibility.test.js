const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const fs = require('node:fs');

process.env.TEST_ENV = '1';
process.env.ADAPTER_PORT = '19434';
process.env.LLAMA_HOST = '127.0.0.1';
process.env.LLAMA_PORT = '9090';
process.env.AI_MODEL_NAME = 'qwen2.5:0.5b';

const adapterServer = require('../android/ai-adapter.js');

test.before((_, done) => {
  adapterServer.listen(19434, '127.0.0.1', done);
});

test.after((_, done) => {
  adapterServer.close(done);
});

test('Android Compatibility: ai-adapter maps Ollama GET /api/tags contract', async () => {
  const mockLlama = http.createServer((req, res) => {
    if (req.url === '/health') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok' }));
      return;
    }
    res.writeHead(404);
    res.end();
  });

  await new Promise(resolve => mockLlama.listen(9090, '127.0.0.1', resolve));

  const responseData = await new Promise((resolve, reject) => {
    http.get('http://127.0.0.1:19434/api/tags', (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(JSON.parse(data)));
    }).on('error', reject);
  });

  assert.ok(Array.isArray(responseData.models), 'models harus berupa array');
  assert.equal(responseData.models.length, 1);
  assert.equal(responseData.models[0].name, 'qwen2.5:0.5b');

  await new Promise(resolve => mockLlama.close(resolve));
});

test('Android Compatibility: ai-adapter translates POST /api/chat to llama format', async () => {
  let receivedPayload = null;
  const mockLlama = http.createServer((req, res) => {
    if (req.url === '/v1/chat/completions' && req.method === 'POST') {
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => {
        receivedPayload = JSON.parse(body);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          choices: [
            {
              message: {
                role: 'assistant',
                content: 'Halo dari mock llama Android!'
              }
            }
          ]
        }));
      });
      return;
    }
    res.writeHead(404);
    res.end();
  });

  await new Promise(resolve => mockLlama.listen(9090, '127.0.0.1', resolve));

  const chatPayload = JSON.stringify({
    model: 'qwen2.5:0.5b',
    messages: [
      { role: 'system', content: 'Kamu adalah SI BONTOT' },
      { role: 'user', content: 'Halo Bro' }
    ],
    options: {
      num_predict: 40,
      temperature: 0.3
    }
  });

  const chatResponse = await new Promise((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1',
      port: 19434,
      path: '/api/chat',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(chatPayload)
      }
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(JSON.parse(data)));
    });
    req.on('error', reject);
    req.write(chatPayload);
    req.end();
  });

  assert.ok(receivedPayload, 'Payload harus diterima oleh mock llama');
  assert.equal(receivedPayload.messages.length, 2);
  assert.equal(receivedPayload.max_tokens, 40);
  assert.equal(chatResponse.message.content, 'Halo dari mock llama Android!');
  assert.equal(chatResponse.model, 'qwen2.5:0.5b');

  await new Promise(resolve => mockLlama.close(resolve));
});

test('Android Compatibility: Client static dist exists and has valid index.html', () => {
  const distHtml = path.join(__dirname, '../client/dist/index.html');
  assert.ok(fs.existsSync(distHtml), 'client/dist/index.html harus tersedia setelah build');
  const htmlContent = fs.readFileSync(distHtml, 'utf8');
  assert.ok(htmlContent.includes('<!doctype html>'), 'index.html harus berupa dokumen HTML yang valid');
});

test('Android Compatibility: ai-adapter responds to /health and /api/version probes', async () => {
  const versionData = await new Promise((resolve, reject) => {
    http.get('http://127.0.0.1:19434/api/version', (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(JSON.parse(data)));
    }).on('error', reject);
  });
  assert.equal(typeof versionData.version, 'string');

  const healthData = await new Promise((resolve, reject) => {
    http.get('http://127.0.0.1:19434/health', (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => resolve(JSON.parse(data)));
    }).on('error', reject);
  });
  assert.equal(healthData.status, 'ok');
  assert.equal(healthData.adapter, true);
});

test('Android Compatibility: ai-adapter translates POST /api/generate to llama format', async () => {
  let receivedPayload = null;
  const mockLlama = http.createServer((req, res) => {
    if (req.url === '/v1/chat/completions' && req.method === 'POST') {
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => {
        receivedPayload = JSON.parse(body);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          choices: [
            {
              message: {
                role: 'assistant',
                content: 'Halo dari generate mock!'
              }
            }
          ]
        }));
      });
      return;
    }
    res.writeHead(404);
    res.end();
  });

  await new Promise(resolve => mockLlama.listen(9090, '127.0.0.1', resolve));

  const generatePayload = JSON.stringify({
    prompt: 'Tes prompt generate',
    options: { num_predict: 50 }
  });

  const generateResponse = await new Promise((resolve, reject) => {
    const req = http.request({
      host: '127.0.0.1',
      port: 19434,
      path: '/api/generate',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(generatePayload)
      }
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve(JSON.parse(data)));
    });
    req.on('error', reject);
    req.write(generatePayload);
    req.end();
  });

  assert.ok(receivedPayload, 'Payload generate harus diterima');
  assert.equal(generateResponse.response, 'Halo dari generate mock!');
  assert.equal(generateResponse.done, true);

  await new Promise(resolve => mockLlama.close(resolve));
});

