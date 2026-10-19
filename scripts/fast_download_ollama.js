const fs = require('fs');
const path = require('path');
const https = require('https');
const { execSync } = require('child_process');

const TEMP_DIR = process.env.TEMP || 'C:\\Windows\\Temp';
const TARGET_FILE = path.join(TEMP_DIR, 'OllamaSetup.exe');
const STATE_FILE = path.join(TEMP_DIR, 'ollama_chunks_state.json');
const INITIAL_URL = 'https://ollama.com/download/OllamaSetup.exe';
const CONCURRENCY = 32;
const CHUNK_SIZE = 8 * 1024 * 1024; // 8MB per chunk

function getFinalUrl(url) {
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        resolve(getFinalUrl(res.headers.location));
      } else if (res.statusCode === 200) {
        resolve({ url, contentLength: Number(res.headers['content-length']) });
      } else {
        reject(new Error(`Failed to resolve URL, status: ${res.statusCode}`));
      }
    }).on('error', reject);
  });
}

function downloadChunk(finalUrl, fd, chunkIndex, start, end, onProgress) {
  return new Promise((resolve, reject) => {
    const headers = { Range: `bytes=${start}-${end}` };
    const req = https.get(finalUrl, { headers }, (res) => {
      if (res.statusCode !== 206 && res.statusCode !== 200) {
        return reject(new Error(`Chunk ${chunkIndex} failed with status: ${res.statusCode}`));
      }

      let offset = start;
      res.on('data', (buf) => {
        try {
          fs.writeSync(fd, buf, 0, buf.length, offset);
          offset += buf.length;
          onProgress(buf.length);
        } catch (e) {
          reject(e);
        }
      });

      res.on('end', () => {
        resolve();
      });
    });

    req.on('error', reject);
    req.setTimeout(45000, () => {
      req.destroy();
      reject(new Error(`Chunk ${chunkIndex} timed out`));
    });
  });
}

async function main() {
  console.log('[1/5] Mengambil URL unduhan resmi Ollama Windows...');
  const { url: finalUrl, contentLength } = await getFinalUrl(INITIAL_URL);
  console.log(`[2/5] Ukuran installer: ${(contentLength / (1024 * 1024)).toFixed(2)} MB`);

  let completedIndices = new Set();
  if (fs.existsSync(STATE_FILE)) {
    try {
      const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
      if (Array.isArray(data)) completedIndices = new Set(data);
    } catch (e) {}
  }

  let fd;
  if (!fs.existsSync(TARGET_FILE) || fs.statSync(TARGET_FILE).size !== contentLength) {
    fd = fs.openSync(TARGET_FILE, 'w');
    fs.ftruncateSync(fd, contentLength);
    completedIndices.clear();
  } else {
    fd = fs.openSync(TARGET_FILE, 'r+');
  }

  const allChunks = [];
  let start = 0;
  let idx = 0;
  while (start < contentLength) {
    const end = Math.min(start + CHUNK_SIZE - 1, contentLength - 1);
    allChunks.push({ idx, start, end });
    start = end + 1;
    idx++;
  }

  const pendingChunks = allChunks.filter(c => !completedIndices.has(c.idx));
  const totalChunks = allChunks.length;
  let downloadedBytes = (totalChunks - pendingChunks.length) * CHUNK_SIZE;

  console.log(`[3/5] Melanjutkan unduhan dengan ${CONCURRENCY} koneksi paralel (${completedIndices.size}/${totalChunks} blok selesai)...`);

  const startTime = Date.now();
  let lastLogTime = Date.now();

  function onProgress(bytes) {
    downloadedBytes += bytes;
    const now = Date.now();
    if (now - lastLogTime > 2500) {
      lastLogTime = now;
      const elapsed = (now - startTime) / 1000;
      const speed = (downloadedBytes - (totalChunks - pendingChunks.length) * CHUNK_SIZE) / elapsed / (1024 * 1024);
      const pct = Math.min(100, (downloadedBytes / contentLength) * 100).toFixed(1);
      const remainingBytes = Math.max(0, contentLength - downloadedBytes);
      const eta = speed > 0 ? (remainingBytes / (speed * 1024 * 1024)).toFixed(0) : '...';
      console.log(`Progress: ${pct}% (${(downloadedBytes / (1024 * 1024)).toFixed(1)} MB) | Kecepatan: ${speed.toFixed(2)} MB/s | Estimasi: ${eta}s`);
    }
  }

  let queueIndex = 0;
  async function worker() {
    while (queueIndex < pendingChunks.length) {
      const current = pendingChunks[queueIndex++];
      let retries = 3;
      while (retries > 0) {
        try {
          await downloadChunk(finalUrl, fd, current.idx, current.start, current.end, onProgress);
          completedIndices.add(current.idx);
          if (completedIndices.size % 5 === 0) {
            fs.writeFileSync(STATE_FILE, JSON.stringify([...completedIndices]));
          }
          break;
        } catch (err) {
          retries--;
          if (retries === 0) throw err;
          await new Promise(r => setTimeout(r, 1000));
        }
      }
    }
  }

  const workers = [];
  for (let i = 0; i < CONCURRENCY; i++) {
    workers.push(worker());
  }

  await Promise.all(workers);
  fs.closeSync(fd);
  if (fs.existsSync(STATE_FILE)) fs.unlinkSync(STATE_FILE);

  console.log(`[4/5] Unduhan selesai 100%! Menjalankan installer resmi Ollama...`);
  try {
    execSync(`"${TARGET_FILE}" /silent`, { timeout: 120000 });
    console.log('[5/5] Instalasi Ollama selesai!');
  } catch (err) {
    console.log('Installer dieksekusi.');
  }
}

main().catch((err) => {
  console.error('Download error:', err);
  process.exit(1);
});
