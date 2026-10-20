/**
 * SI BONTOT Android AI Adapter
 * 
 * Jembatan ultra-ringan antara SI BONTOT (format Ollama API) dan engine AI Android (llama-server / OpenAI format).
 * Hanya menggunakan modul bawaan Node.js (http), konsumsi RAM < 20 MB.
 * Mencegah kebutuhan instalasi Ollama desktop yang berat di Android.
 */

const http = require('http');

const PORT = process.env.ADAPTER_PORT || 11434;
function getLlamaHost() { return process.env.LLAMA_HOST || '127.0.0.1'; }
function getLlamaPort() { return process.env.LLAMA_PORT || 8080; }
function getModelName() { return process.env.AI_MODEL_NAME || 'qwen2.5:0.5b'; }

const server = http.createServer((req, res) => {
  const llamaHost = getLlamaHost();
  const llamaPort = getLlamaPort();
  const modelName = getModelName();

  // 1. GET /api/tags -> Format status model Ollama
  if (req.method === 'GET' && req.url === '/api/tags') {
    const checkReq = http.request({
      host: llamaHost,
      port: llamaPort,
      path: '/health',
      method: 'GET',
      timeout: 2500
    }, (llamaRes) => {
      let data = '';
      llamaRes.on('data', c => { data += c; });
      llamaRes.on('end', () => {
        // llama-server returns status 200 {"status":"ok"} when model is ready
        if (llamaRes.statusCode >= 200 && llamaRes.statusCode < 300) {
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({
            models: [
              {
                name: modelName,
                model: modelName,
                modified_at: new Date().toISOString(),
                size: 470000000,
                details: { format: 'gguf', family: 'qwen2', parameter_size: '0.5B' }
              }
            ]
          }));
        } else {
          // llama-server still loading or busy
          res.writeHead(200, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ models: [], status: 'loading' }));
        }
      });
    });

    checkReq.on('error', () => {
      // llama-server offline
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ models: [], status: 'offline' }));
    });

    checkReq.on('timeout', () => {
      checkReq.destroy();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ models: [], status: 'timeout' }));
    });

    checkReq.end();
    return;
  }

  // 2. GET /api/version -> Ollama version probe
  if (req.method === 'GET' && req.url === '/api/version') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ version: '0.3.14' }));
    return;
  }

  // 3. GET /health -> Adapter diagnostic probe
  if (req.method === 'GET' && (req.url === '/health' || req.url === '/')) {
    const probeReq = http.request({
      host: llamaHost,
      port: llamaPort,
      path: '/health',
      method: 'GET',
      timeout: 1500
    }, (probeRes) => {
      const isLlamaUp = probeRes.statusCode >= 200 && probeRes.statusCode < 300;
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'ok',
        adapter: true,
        modelName: modelName,
        llamaServer: { host: llamaHost, port: llamaPort, connected: isLlamaUp, statusCode: probeRes.statusCode }
      }));
    });

    probeReq.on('error', () => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        status: 'ok',
        adapter: true,
        modelName: modelName,
        llamaServer: { host: llamaHost, port: llamaPort, connected: false }
      }));
    });

    probeReq.end();
    return;
  }

  // 4. POST /api/chat -> Terjemahkan dari Ollama format ke llama-server (/v1/chat/completions)
  if (req.method === 'POST' && req.url === '/api/chat') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const parsed = JSON.parse(body);
        const messages = parsed.messages || [];
        const options = parsed.options || {};

        const llamaPayload = JSON.stringify({
          model: modelName,
          messages: messages,
          max_tokens: options.num_predict || 80,
          temperature: typeof options.temperature === 'number' ? options.temperature : 0.3,
          top_p: typeof options.top_p === 'number' ? options.top_p : 0.85,
          stream: false
        });

        const llamaReq = http.request({
          host: llamaHost,
          port: llamaPort,
          path: '/v1/chat/completions',
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(llamaPayload)
          },
          timeout: 45000
        }, (llamaRes) => {
          let llamaData = '';
          llamaRes.on('data', c => { llamaData += c; });
          llamaRes.on('end', () => {
            try {
              const llamaParsed = JSON.parse(llamaData);
              const replyText = llamaParsed.choices?.[0]?.message?.content || '';
              
              res.writeHead(200, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({
                model: modelName,
                created_at: new Date().toISOString(),
                message: {
                  role: 'assistant',
                  content: replyText
                },
                done: true
              }));
            } catch (e) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: 'Gagal mem-parsing respons llama-server: ' + e.message }));
            }
          });
        });

        llamaReq.on('error', (err) => {
          res.writeHead(503, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Koneksi ke llama-server port ' + llamaPort + ' gagal: ' + err.message }));
        });

        llamaReq.on('timeout', () => {
          llamaReq.destroy();
          res.writeHead(504, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'llama-server timeout saat inferensi' }));
        });

        llamaReq.write(llamaPayload);
        llamaReq.end();
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Payload tidak valid: ' + err.message }));
      }
    });
    return;
  }

  // 5. POST /api/generate -> Terjemahkan dari Ollama prompt ke llama-server (/v1/chat/completions)
  if (req.method === 'POST' && req.url === '/api/generate') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const parsed = JSON.parse(body);
        const prompt = parsed.prompt || '';
        const system = parsed.system || '';
        const options = parsed.options || {};

        const messages = [];
        if (system) messages.push({ role: 'system', content: system });
        messages.push({ role: 'user', content: prompt });

        const llamaPayload = JSON.stringify({
          model: modelName,
          messages: messages,
          max_tokens: options.num_predict || 80,
          temperature: typeof options.temperature === 'number' ? options.temperature : 0.3,
          top_p: typeof options.top_p === 'number' ? options.top_p : 0.85,
          stream: false
        });

        const llamaReq = http.request({
          host: llamaHost,
          port: llamaPort,
          path: '/v1/chat/completions',
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(llamaPayload)
          },
          timeout: 45000
        }, (llamaRes) => {
          let llamaData = '';
          llamaRes.on('data', c => { llamaData += c; });
          llamaRes.on('end', () => {
            try {
              const llamaParsed = JSON.parse(llamaData);
              const replyText = llamaParsed.choices?.[0]?.message?.content || '';
              
              res.writeHead(200, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({
                model: modelName,
                created_at: new Date().toISOString(),
                response: replyText,
                done: true
              }));
            } catch (e) {
              res.writeHead(500, { 'Content-Type': 'application/json' });
              res.end(JSON.stringify({ error: 'Gagal mem-parsing respons llama-server: ' + e.message }));
            }
          });
        });

        llamaReq.on('error', (err) => {
          res.writeHead(503, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Koneksi ke llama-server port ' + llamaPort + ' gagal: ' + err.message }));
        });

        llamaReq.on('timeout', () => {
          llamaReq.destroy();
          res.writeHead(504, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'llama-server timeout saat inferensi' }));
        });

        llamaReq.write(llamaPayload);
        llamaReq.end();
      } catch (err) {
        res.writeHead(400, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Payload tidak valid: ' + err.message }));
      }
    });
    return;
  }

  // Fallback
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Endpoint tidak ditemukan' }));
});

server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.error(`[${new Date().toISOString()}] [AI-Adapter ERROR] Port ${PORT} sudah digunakan oleh proses lain!`);
    process.exit(1);
  } else {
    console.error(`[${new Date().toISOString()}] [AI-Adapter ERROR]`, err);
  }
});

process.on('SIGTERM', () => {
  console.log(`[${new Date().toISOString()}] [AI-Adapter] Menerima SIGTERM. Menutup server adapter...`);
  server.close(() => process.exit(0));
});

process.on('SIGINT', () => {
  console.log(`[${new Date().toISOString()}] [AI-Adapter] Menerima SIGINT. Menutup server adapter...`);
  server.close(() => process.exit(0));
});

process.on('SIGHUP', () => {
  console.log(`[${new Date().toISOString()}] [AI-Adapter] SIGHUP diterima, mengabaikan sinyal agar tetap aktif di latar belakang.`);
});

process.on('uncaughtException', (err) => {
  console.error(`[${new Date().toISOString()}] [AI-Adapter FATAL]`, err.message);
});

// Start listening if executed directly
if (require.main === module || !process.env.TEST_ENV) {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`[${new Date().toISOString()}] [AI-Adapter Android] Berjalan di http://127.0.0.1:${PORT}`);
    console.log(`[AI-Adapter Android] Menghubungkan ke llama-server di ${getLlamaHost()}:${getLlamaPort()}`);
  });
}

module.exports = server;
