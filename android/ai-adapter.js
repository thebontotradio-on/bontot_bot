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
      timeout: 2000
    }, (llamaRes) => {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        models: [
          {
            name: modelName,
            model: modelName,
            modified_at: new Date().toISOString(),
            size: 398000000,
            details: { format: 'gguf', family: 'qwen2', parameter_size: '0.5B' }
          }
        ]
      }));
    });

    checkReq.on('error', () => {
      // llama-server offline
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ models: [] }));
    });

    checkReq.on('timeout', () => {
      checkReq.destroy();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ models: [] }));
    });

    checkReq.end();
    return;
  }

  // 2. POST /api/chat -> Terjemahkan dari Ollama format ke llama-server (/v1/chat/completions)
  if (req.method === 'POST' && req.url === '/api/chat') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const parsed = JSON.parse(body);
        const messages = parsed.messages || [];
        const options = parsed.options || {};

        const llamaPayload = JSON.stringify({
          messages: messages,
          max_tokens: options.num_predict || 60,
          temperature: options.temperature || 0.3,
          top_p: options.top_p || 0.85,
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
              res.end(JSON.stringify({ error: 'Gagal mem-parsing respons llama-server' }));
            }
          });
        });

        llamaReq.on('error', (err) => {
          res.writeHead(503, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: 'Koneksi ke llama-server gagal: ' + err.message }));
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
        res.end(JSON.stringify({ error: 'Payload tidak valid' }));
      }
    });
    return;
  }

  // Fallback
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Endpoint tidak ditemukan' }));
});

// Start listening if executed directly
if (require.main === module || !process.env.TEST_ENV) {
  server.listen(PORT, '127.0.0.1', () => {
    console.log(`[AI-Adapter Android] Berjalan di http://127.0.0.1:${PORT}`);
    console.log(`[AI-Adapter Android] Menghubungkan ke llama-server di ${getLlamaHost()}:${getLlamaPort()}`);
  });
}

module.exports = server;
