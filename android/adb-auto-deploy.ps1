# ==============================================================================
# SI BONTOT - Zero-Command ADB Automated Deployer (Resilient & Defensive)
# Memeriksa koneksi HP Android, mengunduh official adb jika belum ada,
# menangani unauthorized/disconnected, memverifikasi Termux, dan mentransfer bundle.
# ==============================================================================

$RootPath = Resolve-Path "$PSScriptRoot\.."
$ScratchDir = "$RootPath\scratch"
$ToolsDir = "$ScratchDir\platform-tools"
$AdbExe = "$ToolsDir\adb.exe"

# 1. Cari ADB di sistem atau unduh resmi dari Google
if (Get-Command adb -ErrorAction SilentlyContinue) {
    $AdbCmd = "adb"
} elseif (Test-Path $AdbExe) {
    $AdbCmd = $AdbExe
} else {
    Write-Host "[1/5] Mengunduh Google Platform-Tools resmi (adb.exe)..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $ScratchDir -Force | Out-Null
    $ZipPath = "$ScratchDir\platform-tools.zip"
    $GoogleUrl = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
    
    try {
        Invoke-WebRequest -Uri $GoogleUrl -OutFile $ZipPath -UseBasicParsing -TimeoutSec 30
        Expand-Archive -Path $ZipPath -DestinationPath $ScratchDir -Force
        Remove-Item $ZipPath -Force
        $AdbCmd = $AdbExe
    } catch {
        Write-Host "[ERROR] Gagal mengunduh adb.exe dari Google: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Periksa koneksi internet laptop Anda." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "Menggunakan ADB: $AdbCmd" -ForegroundColor Green

# 2. Periksa Koneksi Perangkat Android
Write-Host "[2/5] Memeriksa status perangkat Android..." -ForegroundColor Cyan
$DeviceOutput = & $AdbCmd devices

$AuthorizedDevice = $null
$UnauthorizedDevice = $null

foreach ($line in $DeviceOutput) {
    if ($line -match "(\S+)\s+device$") {
        $AuthorizedDevice = $matches[1]
    } elseif ($line -match "(\S+)\s+unauthorized$") {
        $UnauthorizedDevice = $matches[1]
    }
}

if ($UnauthorizedDevice -and -not $AuthorizedDevice) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host "[PERINGATAN] HP Android terdeteksi ($UnauthorizedDevice) tetapi BELUM DIIZINKAN." -ForegroundColor Yellow
    Write-Host "Tindakan pemilik HP:" -ForegroundColor White
    Write-Host "1. Buka kunci layar HP Android Anda." -ForegroundColor White
    Write-Host "2. Pada pop-up 'Izinkan debugging USB?', centang 'Selalu izinkan dari komputer ini'." -ForegroundColor White
    Write-Host "3. Ketuk 'OK' atau 'Izinkan'." -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Yellow
    exit 3
}

if (-not $AuthorizedDevice) {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host "[INFO] Belum ada HP Android yang terdeteksi via kabel USB." -ForegroundColor Yellow
    Write-Host "Prasyarat sederhana:" -ForegroundColor White
    Write-Host "1. Pasang kabel USB dari HP Android ke laptop." -ForegroundColor White
    Write-Host "2. Di HP: Buka Pengaturan -> Opsi Pengembang -> Aktifkan 'Debugging USB'." -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Yellow
    exit 2
}

Write-Host "[OK] Perangkat Android terhubung & diizinkan: $AuthorizedDevice" -ForegroundColor Green

# 3. Baca Spesifikasi Riil Perangkat Keras
Write-Host "[3/5] Mengukur spesifikasi perangkat nyata dari chipset HP..." -ForegroundColor Cyan
try {
    $Model = & $AdbCmd -s $AuthorizedDevice shell getprop ro.product.model
    $AndroidVer = & $AdbCmd -s $AuthorizedDevice shell getprop ro.build.version.release
    $CpuAbi = & $AdbCmd -s $AuthorizedDevice shell getprop ro.product.cpu.abi
    $MemTotal = & $AdbCmd -s $AuthorizedDevice shell "cat /proc/meminfo | grep MemTotal"
    $DiskFree = & $AdbCmd -s $AuthorizedDevice shell "df -h /data | tail -n 1"

    Write-Host "  - Model HP        : $Model" -ForegroundColor White
    Write-Host "  - Versi Android   : $AndroidVer" -ForegroundColor White
    Write-Host "  - Arsitektur CPU  : $CpuAbi" -ForegroundColor White
    Write-Host "  - Total RAM Fisik : $MemTotal" -ForegroundColor White
    Write-Host "  - Ruang Bebas     : $DiskFree" -ForegroundColor White
} catch {
    Write-Host "[WARNING] Koneksi ke HP terputus saat membaca spesifikasi." -ForegroundColor Yellow
    exit 4
}

# 4. Verifikasi Keberadaan Aplikasi Termux di HP
Write-Host "[4/5] Memeriksa instalasi aplikasi Termux di HP..." -ForegroundColor Cyan
$PkgCheck = & $AdbCmd -s $AuthorizedDevice shell "pm list packages com.termux"
if ($PkgCheck -notmatch "package:com.termux") {
    Write-Host ""
    Write-Host "========================================================================" -ForegroundColor Yellow
    Write-Host "[PERINGATAN] Aplikasi Termux belum terpasang di HP Android!" -ForegroundColor Yellow
    Write-Host "Silakan unduh dan instal Termux APK dari F-Droid:" -ForegroundColor White
    Write-Host "https://f-droid.org/packages/com.termux/" -ForegroundColor Cyan
    Write-Host "Setelah terpasang, buka Termux satu kali lalu jalankan kembali skrip ini." -ForegroundColor White
    Write-Host "========================================================================" -ForegroundColor Yellow
    exit 5
}
Write-Host "[OK] Aplikasi Termux terdeteksi di HP." -ForegroundColor Green

# 5. Transfer Bundle Bersih ke HP Android
Write-Host "[5/5] Mengirimkan paket si-bontot-android-bundle.zip ke HP..." -ForegroundColor Cyan
$BundlePath = "$RootPath\si-bontot-android-bundle.zip"
if (-not (Test-Path $BundlePath)) {
    & powershell -ExecutionPolicy Bypass -File "$RootPath\android\export-package.ps1"
}

$PushResult = & $AdbCmd -s $AuthorizedDevice push $BundlePath /sdcard/Download/si-bontot-android-bundle.zip
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Pengiriman berkas terputus di tengah jalan! Periksa kabel USB." -ForegroundColor Red
    exit 6
}

# Verifikasi integritas ukuran di HP
$RemoteSize = & $AdbCmd -s $AuthorizedDevice shell "wc -c < /sdcard/Download/si-bontot-android-bundle.zip"
$LocalSize = (Get-Item $BundlePath).Length

if ([int64]$RemoteSize -ne $LocalSize) {
    Write-Host "[ERROR] Ukuran berkas di HP ($RemoteSize byte) tidak cocok dengan laptop ($LocalSize byte)!" -ForegroundColor Red
    exit 7
}

Write-Host "[OK] Paket bersih terverifikasi di HP: /sdcard/Download/si-bontot-android-bundle.zip ($LocalSize byte)" -ForegroundColor Green
Write-Host ""
Write-Host "✔ OTOMASI SELESAI TANPA REKAYASA & TANPA PENGGUNA PERLU MENGETIK PERINTAH!" -ForegroundColor Green
