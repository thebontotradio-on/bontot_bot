const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execSync } = require('node:child_process');
const zlib = require('node:zlib');

test('Server Integrity: All server JavaScript files pass node --check syntax audit', () => {
  const serverDir = path.join(__dirname, '../server');
  const serverFiles = ['index.js', 'whatsapp.js', 'ai.js', 'db.js', 'utils.js'];

  for (const file of serverFiles) {
    const fullPath = path.join(serverDir, file);
    assert.ok(fs.existsSync(fullPath), `File ${file} must exist in server/`);

    // Must not throw
    assert.doesNotThrow(() => {
      execSync(`node --check "${fullPath}"`, { stdio: 'pipe' });
    }, `File ${file} failed node --check syntax verification`);
  }
});

test('Server Integrity: server/index.js contains properly closed route handlers and SPA fallback', () => {
  const indexContent = fs.readFileSync(path.join(__dirname, '../server/index.js'), 'utf8');

  // Check allowlist handler closing
  assert.ok(indexContent.includes("app.post('/api/auto-reply/allowlist'"), 'Must contain POST /api/auto-reply/allowlist');
  assert.ok(indexContent.includes('// SPA Fallback for client routing'), 'Must contain SPA Fallback comment');

  // Ensure there is a closing }); between allowlist catch and SPA fallback
  const allowlistBlock = indexContent.slice(
    indexContent.indexOf("app.post('/api/auto-reply/allowlist'"),
    indexContent.indexOf('// SPA Fallback for client routing')
  );
  assert.ok(allowlistBlock.includes('});'), 'POST /api/auto-reply/allowlist must be properly closed with });');
});

test('Server Integrity: si-bontot-android-bundle.zip matches source server/index.js exactly', () => {
  const zipPath = path.join(__dirname, '../si-bontot-android-bundle.zip');
  assert.ok(fs.existsSync(zipPath), 'si-bontot-android-bundle.zip must exist');

  const sourceIndexPath = path.join(__dirname, '../server/index.js');
  const sourceContent = fs.readFileSync(sourceIndexPath);

  // Read ZIP entries using powershell or simple parsing
  const output = execSync(
    'powershell -NoProfile -Command "Add-Type -AssemblyName System.IO.Compression.FileSystem; $zip = [System.IO.Compression.ZipFile]::OpenRead(\'' +
      zipPath.replace(/\\/g, '\\\\') +
      '\'); $e = $zip.Entries | Where-Object { $_.FullName -eq \'server/index.js\' }; Write-Output $e.Length; $zip.Dispose()"',
    { encoding: 'utf8' }
  ).trim();

  const zipEntryLength = parseInt(output, 10);
  assert.equal(zipEntryLength, sourceContent.length, 'server/index.js in ZIP must match source size exactly');
});

test('Server Integrity: Android installer scripts enforce node --check validation before completion', () => {
  const installDirect = fs.readFileSync(path.join(__dirname, '../android/install-direct.sh'), 'utf8');
  assert.ok(
    installDirect.includes('node --check "$PROJECT_DIR/server/index.js"'),
    'install-direct.sh must validate node --check server/index.js'
  );
  assert.ok(
    installDirect.includes('VALIDATE_EXIT'),
    'install-direct.sh must track validate-installation.sh exit code'
  );

  const checkReadiness = fs.readFileSync(path.join(__dirname, '../android/check-readiness.sh'), 'utf8');
  assert.ok(
    checkReadiness.includes('node --check'),
    'check-readiness.sh must validate node --check before starting service'
  );
});
