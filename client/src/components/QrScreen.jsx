import React from 'react';
import { QrCode, RefreshCw, Smartphone, ShieldCheck, WifiOff, MessageSquare } from 'lucide-react';

export default function QrScreen({
  status,
  qrCode,
  onRefresh,
  isRefreshing
}) {
  return (
    <div className="flex-1 flex flex-col items-center justify-center p-6 bg-[#0c1317] select-none overflow-y-auto">
      <div className="max-w-xl w-full bg-[#111b21] border border-[#222e35] rounded-3xl p-6 sm:p-10 shadow-2xl text-center">
        {/* App Title */}
        <div className="flex items-center justify-center gap-3 mb-6">
          <div className="w-12 h-12 rounded-2xl bg-gradient-to-tr from-[#00a884] to-[#25d366] flex items-center justify-center shadow-lg shadow-[#00a884]/20">
            <MessageSquare className="w-6 h-6 text-white" />
          </div>
          <div className="text-left">
            <h1 className="text-xl font-bold text-[#e9edef] tracking-wide">WA BONTOT</h1>
            <p className="text-xs text-[#8696a0]">WhatsApp Dashboard & Asisten AI Lokal</p>
          </div>
        </div>

        {/* Status Views */}
        {status === 'qr' && qrCode ? (
          <div>
            <div className="relative inline-block p-4 bg-white rounded-2xl shadow-xl mb-6">
              <img
                src={qrCode}
                alt="Scan WhatsApp QR Code"
                className="w-64 h-64 sm:w-72 sm:h-72 object-contain"
              />
              <div className="absolute inset-0 border-4 border-dashed border-[#00a884]/40 rounded-2xl pointer-events-none" />
            </div>

            <div className="text-left bg-[#182229] border border-[#222e35] rounded-2xl p-5 mb-6 space-y-3">
              <h2 className="text-xs font-semibold uppercase tracking-wider text-[#00a884] flex items-center gap-2">
                <Smartphone className="w-4 h-4" /> Cara Menghubungkan WhatsApp
              </h2>
              <ol className="text-xs text-[#d1d7db] space-y-2 list-decimal list-inside leading-relaxed">
                <li>Buka aplikasi <strong>WhatsApp</strong> di ponsel Anda.</li>
                <li>Buka <strong>Menu (ikon titik tiga)</strong> atau <strong>Pengaturan</strong>.</li>
                <li>Pilih <strong>Perangkat Tertaut (Linked Devices)</strong>.</li>
                <li>Ketuk <strong>Tautkan Perangkat</strong> lalu arahkan kamera ke kode QR di atas.</li>
              </ol>
            </div>

            <div className="flex items-center justify-between text-xs text-[#8696a0]">
              <span className="flex items-center gap-1.5">
                <ShieldCheck className="w-4 h-4 text-emerald-400" /> Sesi tersimpan aman di server lokal
              </span>
              <button
                onClick={onRefresh}
                disabled={isRefreshing}
                className="flex items-center gap-1.5 text-[#00a884] hover:text-[#02906f] font-medium"
              >
                <RefreshCw className={`w-3.5 h-3.5 ${isRefreshing ? 'animate-spin' : ''}`} />
                Perbarui QR
              </button>
            </div>
          </div>
        ) : status === 'connecting' ? (
          <div className="py-12 flex flex-col items-center">
            <div className="w-14 h-14 border-4 border-[#00a884] border-t-transparent rounded-full animate-spin mb-6" />
            <h2 className="text-lg font-semibold text-[#e9edef] mb-2">Menghubungkan ke WhatsApp...</h2>
            <p className="text-xs text-[#8696a0] max-w-sm">
              Menyiapkan sesi autentikasi dan memuat socket koneksi Baileys. Mohon tunggu sebentar.
            </p>
          </div>
        ) : (
          <div className="py-10 flex flex-col items-center">
            <div className="w-16 h-16 rounded-full bg-amber-500/10 border border-amber-500/20 flex items-center justify-center text-amber-400 mb-5">
              <WifiOff className="w-8 h-8" />
            </div>
            <h2 className="text-lg font-semibold text-[#e9edef] mb-2">Koneksi Belum Terhubung</h2>
            <p className="text-xs text-[#8696a0] max-w-sm mb-6">
              Sesi WhatsApp belum terhubung atau baru saja di-reset. Klik tombol di bawah untuk membuat QR Code baru.
            </p>
            <button
              onClick={onRefresh}
              disabled={isRefreshing}
              className="px-6 py-2.5 rounded-xl bg-[#00a884] hover:bg-[#02906f] text-white font-medium text-xs flex items-center gap-2 shadow-lg shadow-[#00a884]/20 transition"
            >
              <RefreshCw className={`w-4 h-4 ${isRefreshing ? 'animate-spin' : ''}`} />
              Muat Ulang Kode QR
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
