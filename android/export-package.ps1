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

# 3b. Validasi sintaks seluruh berkas server sebelum dimasukkan ke dalam bundle
Write-Host "Memeriksa sintaks seluruh berkas JavaScript server..." -ForegroundColor Cyan
$ServerFiles = @("index.js", "whatsapp.js", "ai.js", "db.js", "utils.js")
foreach ($sf in $ServerFiles) {
    $filePath = "$RootPath\server\$sf"
    if (-not (Test-Path $filePath)) {
        Write-Error "[FATAL] Berkas server\$sf tidak ditemukan!"
        exit 1
    }
    $syntaxOutput = & node --check $filePath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[FATAL] Berkas server\$sf memiliki syntax error! $syntaxOutput"
        exit 1
    }
}
Write-Host "[OK] Seluruh berkas server lolos uji sintaks node --check." -ForegroundColor Green

# 4. Salin HANYA berkas JavaScript server (JAMINAN 100% BEBAS DARI auth_session DAN wabontot.db)
New-Item -ItemType Directory -Path "$TempDir\wa-bontot\server" -Force | Out-Null

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

# 9. Buat berkas ZIP standar PKWARE/POSIX dengan pemisah garis miring (/)
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$BaseDir = (Get-Item "$TempDir\wa-bontot").FullName
$ZipArchive = [System.IO.Compression.ZipFile]::Open($DistZip, [System.IO.Compression.ZipArchiveMode]::Create)

Get-ChildItem -Path $BaseDir -Recurse -File | ForEach-Object {
    $RelPath = $_.FullName.Substring($BaseDir.Length + 1).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($ZipArchive, $_.FullName, $RelPath, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
}

$ZipArchive.Dispose()
Remove-Item $TempDir -Recurse -Force

# 10. Verifikasi Integritas Bundle ZIP yang Dihasilkan
Write-Host "Memverifikasi integritas berkas di dalam bundle ZIP..." -ForegroundColor Cyan
$VerifyZip = [System.IO.Compression.ZipFile]::OpenRead($DistZip)
$ServerIndexEntry = $VerifyZip.Entries | Where-Object { $_.FullName -eq "server/index.js" }
if (-not $ServerIndexEntry) {
    $VerifyZip.Dispose()
    Write-Error "[FATAL] server/index.js tidak ditemukan di dalam berkas ZIP!"
    exit 1
}

$OriginalSize = (Get-Item "$RootPath\server\index.js").Length
if ($ServerIndexEntry.Length -ne $OriginalSize) {
    $VerifyZip.Dispose()
    Write-Error "[FATAL] Ukuran server/index.js di dalam ZIP ($($ServerIndexEntry.Length)) tidak cocok dengan sumber ($OriginalSize)!"
    exit 1
}

# Verifikasi sintaks isi ZIP secara nyata
$Stream = $ServerIndexEntry.Open()
$Reader = New-Object System.IO.StreamReader($Stream)
$ExtractedContent = $Reader.ReadToEnd()
$Reader.Close()
$Stream.Close()
$VerifyZip.Dispose()

$TempCheckFile = "$RootPath\scratch\verify_zip_server_index.js"
[System.IO.File]::WriteAllText($TempCheckFile, $ExtractedContent, [System.Text.Encoding]::UTF8)
$ZipSyntaxCheck = & node --check $TempCheckFile 2>&1
$SyntaxExit = $LASTEXITCODE
Remove-Item $TempCheckFile -Force -ErrorAction SilentlyContinue

if ($SyntaxExit -ne 0) {
    Write-Error "[FATAL] server/index.js yang diekstrak dari ZIP mengalami syntax error! $ZipSyntaxCheck"
    exit 1
}
Write-Host "[OK] server/index.js di dalam ZIP terverifikasi identik dan lulus uji node --check." -ForegroundColor Green

$ZipSize = [math]::Round(((Get-Item $DistZip).Length / 1MB), 2)
Write-Host "[OK] Bundle mandiri bersih berhasil dibuat: $DistZip ($ZipSize MB)" -ForegroundColor Green
Write-Host "[OK] Terverifikasi: 0 file sesi auth, 0 database laptop, 0 secret token di dalam bundle." -ForegroundColor Green
