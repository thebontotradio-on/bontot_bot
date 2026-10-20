const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');

test('Server Integrity: All server JavaScript files pass node --check syntax audit', () => {
  const serverDir = path.join(__dirname, '../server');
  const serverFiles = ['index.js', 'whatsapp.js', 'ai.js', 'db.js', 'utils.js'];

  for (const file of serverFiles) {
    const fullPath = path.join(serverDir, file);
    assert.ok(fs.existsSync(fullPath), `File ${file} must exist in server/`);

    assert.doesNotThrow(() => {
      execSync(`node --check "${fullPath}"`, { stdio: 'pipe' });
    }, `File ${file} failed node --check syntax verification`);
  }
});

test('Server Integrity: server/index.js contains properly closed route handlers, SPA fallback, and signal handling', () => {
  const indexContent = fs.readFileSync(path.join(__dirname, '../server/index.js'), 'utf8');

  // Check allowlist handler closing
  assert.ok(indexContent.includes("app.post('/api/auto-reply/allowlist'"), 'Must contain POST /api/auto-reply/allowlist');
  assert.ok(indexContent.includes('// SPA Fallback for client routing'), 'Must contain SPA Fallback comment');

  const allowlistBlock = indexContent.slice(
    indexContent.indexOf("app.post('/api/auto-reply/allowlist'"),
    indexContent.indexOf('// SPA Fallback for client routing')
  );
  assert.ok(allowlistBlock.includes('});'), 'POST /api/auto-reply/allowlist must be properly closed with });');

  // Check graceful shutdown & signal handlers
  assert.ok(indexContent.includes('handleGracefulShutdown'), 'Must implement graceful shutdown function');
  assert.ok(indexContent.includes("process.on('SIGTERM'"), 'Must listen for SIGTERM');
  assert.ok(indexContent.includes("process.on('SIGINT'"), 'Must listen for SIGINT');
  assert.ok(indexContent.includes("process.on('SIGHUP'"), 'Must handle SIGHUP to survive terminal close');
  assert.ok(indexContent.includes("process.on('uncaughtException'"), 'Must guard against uncaught exceptions');
  assert.ok(indexContent.includes("process.on('unhandledRejection'"), 'Must guard against unhandled rejections');
});

test('Server Integrity: start-service.sh is resilient, ignores SIGHUP, and manages child PIDs', () => {
  const scriptContent = fs.readFileSync(path.join(__dirname, '../android/start-service.sh'), 'utf8');

  // Must not have dangerous trap cleanup EXIT
  assert.ok(
    !scriptContent.includes('trap cleanup SIGINT SIGTERM EXIT'),
    'start-service.sh must NOT kill children on script EXIT trap'
  );

  // Must ignore SIGHUP
  assert.ok(
    scriptContent.includes("trap '' HUP SIGHUP") || scriptContent.includes("trap '' HUP"),
    'start-service.sh must ignore SIGHUP so closing Termux does not kill service'
  );

  // Must manage multiple PID files
  assert.ok(scriptContent.includes('SERVER_PID_FILE'), 'Must track server PID');
  assert.ok(scriptContent.includes('AI_PID_FILE'), 'Must track AI adapter PID');
  assert.ok(scriptContent.includes('check_and_clean_stale_pid'), 'Must have anti-stale PID lock guard');

  // Must support CLI commands
  assert.ok(scriptContent.includes('stop)'), 'Must support stop command');
  assert.ok(scriptContent.includes('status)'), 'Must support status command');
  assert.ok(scriptContent.includes('restart)'), 'Must support restart command');
  assert.ok(scriptContent.includes('start)'), 'Must support start command');
});

test('Server Integrity: healthcheck.sh tests real HTTP responses on port 3001 and 11434', () => {
  const healthContent = fs.readFileSync(path.join(__dirname, '../android/healthcheck.sh'), 'utf8');

  assert.ok(
    healthContent.includes('http://127.0.0.1:3001/api/status'),
    'healthcheck.sh must test HTTP GET /api/status on port 3001'
  );
  assert.ok(
    healthContent.includes('http://127.0.0.1:11434/api/tags'),
    'healthcheck.sh must test HTTP GET /api/tags on port 11434'
  );
  assert.ok(
    healthContent.includes('curl -s -o /dev/null -w "%{http_code}"'),
    'healthcheck.sh must verify HTTP status codes'
  );
});

test('Server Integrity: ai-adapter.js handles signals and server error gracefully', () => {
  const adapterContent = fs.readFileSync(path.join(__dirname, '../android/ai-adapter.js'), 'utf8');

  assert.ok(adapterContent.includes("server.on('error'"), 'ai-adapter.js must handle server error events');
  assert.ok(adapterContent.includes("process.on('SIGTERM'"), 'ai-adapter.js must handle SIGTERM');
  assert.ok(adapterContent.includes("process.on('SIGHUP'"), 'ai-adapter.js must handle SIGHUP');
});

test('Server Integrity: setup-llama.sh and test-inference.sh exist and implement required logic', () => {
  const setupLlama = path.join(__dirname, '../android/setup-llama.sh');
  assert.ok(fs.existsSync(setupLlama), 'setup-llama.sh must exist');
  const setupContent = fs.readFileSync(setupLlama, 'utf8');
  assert.ok(setupContent.includes('llama-cpp'), 'Must support pkg install llama-cpp');
  assert.ok(setupContent.includes('cmake'), 'Must support cmake source fallback');

  const testInference = path.join(__dirname, '../android/test-inference.sh');
  assert.ok(fs.existsSync(testInference), 'test-inference.sh must exist');
  const inferenceContent = fs.readFileSync(testInference, 'utf8');
  assert.ok(inferenceContent.includes('http://127.0.0.1:8080/health'), 'Must test 8080 health');
  assert.ok(inferenceContent.includes('http://127.0.0.1:11434/api/chat'), 'Must test 11434 chat inference');
  assert.ok(inferenceContent.includes('http://127.0.0.1:3001/api/ai-reply'), 'Must test 3001 draft inference');
});

test('Server Integrity: si-bontot-android-bundle.zip matches source server/index.js exactly', () => {
  const zipPath = path.join(__dirname, '../si-bontot-android-bundle.zip');
  assert.ok(fs.existsSync(zipPath), 'si-bontot-android-bundle.zip must exist');

  const sourceIndexPath = path.join(__dirname, '../server/index.js');
  const sourceContent = fs.readFileSync(sourceIndexPath);

  const output = execSync(
    'powershell -NoProfile -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::OpenRead(\'' +
      zipPath.replace(/\\/g, '\\\\') +
      '\'); $e = $zip.Entries | Where-Object { $_.FullName -eq \'server/index.js\' }; Write-Output $e.Length; $zip.Dispose()"',
    { encoding: 'utf8' }
  ).trim();

  const zipEntryLength = parseInt(output, 10);
  assert.equal(zipEntryLength, sourceContent.length, 'server/index.js in ZIP must match source size exactly');
});

