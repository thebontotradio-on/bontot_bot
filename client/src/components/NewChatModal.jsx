import React, { useState } from 'react';
import { X, Send, UserPlus, Phone } from 'lucide-react';

export default function NewChatModal({ isOpen, onClose, onStartChat }) {
  const [phoneNumber, setPhoneNumber] = useState('');
  const [firstMessage, setFirstMessage] = useState('');
  const [error, setError] = useState('');

  if (!isOpen) return null;

  const handleSubmit = (e) => {
    e.preventDefault();
    setError('');

    const cleanNumber = phoneNumber.trim().replace(/[^0-9]/g, '');
    if (!cleanNumber || cleanNumber.length < 7) {
      setError('Masukkan nomor telepon WhatsApp yang valid.');
      return;
    }

    if (!firstMessage.trim()) {
      setError('Pesan awal tidak boleh kosong.');
      return;
    }

    onStartChat(phoneNumber.trim(), firstMessage.trim());
    setPhoneNumber('');
    setFirstMessage('');
    onClose();
  };

  return (
    <div
      style={{ position: 'fixed', inset: 0, zIndex: 9999 }}
      className="bg-black/75 backdrop-blur-sm flex items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-[#111b21] border border-[#2a3942] rounded-3xl w-full max-w-md overflow-hidden shadow-2xl animate-in fade-in zoom-in-95 duration-150"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="px-6 py-4 bg-[#202c33] border-b border-[#2a3942] flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-xl bg-[#00a884]/20 border border-[#00a884]/40 flex items-center justify-center text-[#00a884]">
              <UserPlus className="w-4 h-4" />
            </div>
            <h3 className="text-sm font-bold text-[#e9edef]">Mulai Chat Baru</h3>
          </div>
          <button
            onClick={onClose}
            className="p-1 text-[#8696a0] hover:text-[#e9edef] rounded-lg transition"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-xs font-semibold text-[#8696a0] uppercase tracking-wider mb-1.5">
              Nomor WhatsApp Tujuan
            </label>
            <div className="relative">
              <Phone className="w-4 h-4 text-[#8696a0] absolute left-3 top-1/2 -translate-y-1/2" />
              <input
                type="text"
                value={phoneNumber}
                onChange={(e) => setPhoneNumber(e.target.value)}
                placeholder="Contoh: 08123456789 atau 628123456789"
                className="w-full bg-[#182229] border border-[#2a3942] focus:border-[#00a884] rounded-xl pl-9 pr-3 py-2 text-xs sm:text-sm text-[#e9edef] placeholder-[#8696a0] focus:outline-none transition"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-[#8696a0] uppercase tracking-wider mb-1.5">
              Pesan Pertama
            </label>
            <textarea
              rows={3}
              value={firstMessage}
              onChange={(e) => setFirstMessage(e.target.value)}
              placeholder="Tulis pesan pertama Anda..."
              className="w-full bg-[#182229] border border-[#2a3942] focus:border-[#00a884] rounded-xl p-3 text-xs sm:text-sm text-[#e9edef] placeholder-[#8696a0] focus:outline-none transition resize-none"
            />
          </div>

          {error && (
            <p className="text-xs text-red-400">{error}</p>
          )}

          <div className="flex items-center justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-xs font-medium text-[#aebac1] hover:text-white rounded-xl hover:bg-[#202c33] transition"
            >
              Batal
            </button>
            <button
              type="submit"
              className="px-5 py-2 text-xs font-semibold rounded-xl bg-[#00a884] hover:bg-[#02906f] text-white flex items-center gap-2 shadow-lg shadow-[#00a884]/20 transition"
            >
              <Send className="w-3.5 h-3.5" />
              <span>Kirim Pesan</span>
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
