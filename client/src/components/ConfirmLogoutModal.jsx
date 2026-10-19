import React from 'react';
import { AlertTriangle, LogOut, X } from 'lucide-react';

export default function ConfirmLogoutModal({ isOpen, onClose, onConfirm, isLoggingOut }) {
  if (!isOpen) return null;

  return (
    <div
      style={{ position: 'fixed', inset: 0, zIndex: 9999 }}
      className="bg-black/75 backdrop-blur-sm flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-[#111b21] border border-[#2a3942] rounded-3xl w-full max-w-md p-6 shadow-2xl text-center animate-in fade-in zoom-in-95 duration-150"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="w-14 h-14 rounded-2xl bg-red-500/10 border border-red-500/20 text-red-400 flex items-center justify-center mx-auto mb-4">
          <AlertTriangle className="w-7 h-7" />
        </div>

        <h3 className="text-base font-bold text-[#e9edef] mb-2">Konfirmasi Keluar WhatsApp</h3>
        <p className="text-xs text-[#8696a0] mb-6 leading-relaxed">
          Apakah Anda yakin ingin memutuskan sesi WhatsApp ini? Anda harus melakukan scan QR ulang untuk menghubungkan kembali perangkat.
        </p>

        <div className="flex items-center justify-end gap-3">
          <button
            onClick={onClose}
            disabled={isLoggingOut}
            className="flex-1 px-4 py-2.5 text-xs font-semibold text-[#aebac1] hover:text-white rounded-xl hover:bg-[#202c33] transition"
          >
            Batal
          </button>
          <button
            onClick={onConfirm}
            disabled={isLoggingOut}
            className="flex-1 px-4 py-2.5 text-xs font-semibold rounded-xl bg-red-600 hover:bg-red-700 text-white flex items-center justify-center gap-2 shadow-lg shadow-red-600/20 transition disabled:opacity-50"
          >
            <LogOut className="w-4 h-4" />
            <span>{isLoggingOut ? 'Memutuskan...' : 'Ya, Keluar'}</span>
          </button>
        </div>
      </div>
    </div>
  );
}
