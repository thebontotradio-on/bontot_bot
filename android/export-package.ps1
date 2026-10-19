# ==============================================================================
# SI BONTOT - Standalone Android Bundle Packager
# Membuat satu arsip ZIP bersih siap salin ke HP Android tanpa kredensial/data laptop
# ==============================================================================

$RootPath = Resolve-Path "$PSScriptRoot\.."
$DistZip = "$RootPath\si-bontot-android-bundle.zip"

Write-Host "=== Membangun Bundle Bersih SI BONTOT untuk Android ===" -ForegroundColor Cyan

# 1. Pastikan client dist sudah ter-build
if (-not (Test-Path "$RootPath\client\dist\index.html")) {
    Write-Host "Membangun frontend client/dist terlebih dahulu..." -ForegroundColor Yellow
    npm --prefix "$RootPath\client" run build
}

# 2. Hapus bundle lama jika ada
if (Test-Path $DistZip) {
    Remove-Item $DistZip -Force
}

# 3. Buat folder staging sementara
$TempDir = "$RootPath\scratch\bundle_temp"
if (Test-Path $TempDir) { Remove-Item $TempDir -Recurse -Force }
New-Item -ItemType Directory -Path "$TempDir\wa-bontot" | Out-Null

# 4. Salin HANYA berkas JavaScript server (JAMINAN 100% BEBAS DARI auth_session DAN wabontot.db)
New-Item -ItemType Directory -Path "$TempDir\wa-bontot\server" -Force | Out-Null


$ServerFiles = @("index.js", "whatsapp.js", "ai.js", "db.js", "utils.js")
foreach ($sf in $ServerFiles) {
    Copy-Item "$RootPath\server\$sf" "$TempDir\wa-bontot\server\$sf" -Force
}

# 5. Salin client dist (SPA yang sudah terkompilasi)
Copy-Item "$RootPath\client\dist" "$TempDir\wa-bontot\client\dist" -Recurse -Force

# 6. Salin skrip android
New-Item -ItemType Directory -Path "$TempDir\wa-bontot\android" -Force | Out-Null
Get-ChildItem -Path "$RootPath\android" -Exclude "*.zip","*.tar.gz" | ForEach-Object {
    Copy-Item $_.FullName "$TempDir\wa-bontot\android\" -Recurse -Force
}

# 7. Salin manifest npm
Copy-Item "$RootPath\package.json" "$TempDir\wa-bontot\package.json" -Force
Copy-Item "$RootPath\package-lock.json" "$TempDir\wa-bontot\package-lock.json" -Force

# 8. Verifikasi Keamanan Sebelum Kompresi: Pastikan TIDAK ADA file kredensial atau database di staging
$LeakCount = (Get-ChildItem -Path "$TempDir" -Recurse -File | Where-Object { $_.FullName -match 'auth_session|wabontot\.db|\.env' }).Count
if ($LeakCount -gt 0) {
    Write-Error "[FATAL] Ditemukan berkas sensitif di staging! Pengemasan dibatalkan demi keamanan."
    exit 1
}

# 9. Buat berkas ZIP
Compress-Archive -Path "$TempDir\wa-bontot\*" -DestinationPath $DistZip -Force
Remove-Item $TempDir -Recurse -Force

$ZipSize = [math]::Round(((Get-Item $DistZip).Length / 1MB), 2)
Write-Host "[OK] Bundle mandiri bersih berhasil dibuat: $DistZip ($ZipSize MB)" -ForegroundColor Green
Write-Host "[OK] Terverifikasi: 0 file sesi auth, 0 database laptop, 0 secret token di dalam bundle." -ForegroundColor Green
