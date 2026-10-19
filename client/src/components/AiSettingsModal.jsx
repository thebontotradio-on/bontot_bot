import React, { useState, useEffect } from 'react';
import { X, Bot, Check, Save, RefreshCw, Cpu, HardDrive, Terminal, AlertTriangle, ShieldCheck } from 'lucide-react';
import api from '../services/api';

export default function AiSettingsModal({ isOpen, onClose, aiStatus, onRefreshAiStatus }) {
  const [systemPrompt, setSystemPrompt] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [isSaved, setIsSaved] = useState(false);
  const [saveError, setSaveError] = useState(null);

  useEffect(() => {
    if (isOpen) {
      loadSystemPrompt();
    }
  }, [isOpen]);

  const loadSystemPrompt = async () => {
    setIsLoading(true);
    setSaveError(null);
    try {
      const res = await api.getSystemPrompt();
      if (res.data?.success) {
        setSystemPrompt(res.data.systemPrompt || 'You are a helpful assistant.');
      }
    } catch (err) {
      setSaveError('Gagal memuat system prompt dari server.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleSave = async () => {
    setIsLoading(true);
    setSaveError(null);
    setIsSaved(false);

    try {
      const res = await api.setSystemPrompt(systemPrompt);
      if (res.data?.success) {
        setIsSaved(true);
        setTimeout(() => setIsSaved(false), 3000);
      } else {
        setSaveError(res.data?.error || 'Gagal menyimpan pengaturan.');
      }
    } catch (err) {
      setSaveError(err.response?.data?.error || err.message || 'Gagal menghubungi server.');
    } finally {
      setIsLoading(false);
    }
  };

  const handleResetDefault = () => {
    setSystemPrompt('You are a helpful assistant.');
  };

  if (!isOpen) return null;

  return (
    <div
      style={{ position: 'fixed', inset: 0, zIndex: 9999 }}
      className="bg-black/75 backdrop-blur-sm flex items-center justify-center p-4 overflow-y-auto"
      onClick={onClose}
    >
      <div
        className="bg-[#111b21] border border-[#2a3942] rounded-3xl w-full max-w-2xl max-h-[90vh] flex flex-col shadow-2xl overflow-hidden animate-in fade-in zoom-in-95 duration-150"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Modal Header */}
        <div className="px-6 py-4 bg-[#202c33] border-b border-[#2a3942] flex items-center justify-between flex-shrink-0">
          <div className="flex items-center gap-2.5">
            <div className="w-9 h-9 rounded-xl bg-[#00a884]/20 border border-[#00a884]/40 flex items-center justify-center text-[#00a884]">
              <Bot className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-base font-bold text-[#e9edef]">Pengaturan Asisten AI Lokal</h2>
              <p className="text-xs text-[#8696a0]">Karakter & System Prompt Ollama (Gratis & Tanpa API Key)</p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 text-[#8696a0] hover:text-[#e9edef] hover:bg-[#374248] rounded-lg transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Modal Body */}
        <div className="p-6 overflow-y-auto space-y-6 flex-1 text-sm text-[#d1d7db]">
          {/* Status Ollama Card */}
          <div
            className={`p-4 rounded-2xl border transition-all ${
              aiStatus?.available
                ? 'bg-emerald-950/20 border-emerald-500/30 text-emerald-300'
                : 'bg-amber-950/20 border-amber-500/30 text-amber-300'
            }`}
          >
            <div className="flex items-start justify-between gap-3">
              <div className="flex items-start gap-3">
                <div
                  className={`w-3 h-3 rounded-full mt-1 flex-shrink-0 ${
                    aiStatus?.available ? 'bg-emerald-400 animate-pulse' : 'bg-amber-400'
                  }`}
                />
                <div>
                  <h3 className="font-semibold text-xs uppercase tracking-wider text-[#e9edef]">
                    {aiStatus?.available ? 'Ollama Terhubung' : 'Ollama Offline'}
                  </h3>
                  <p className="text-xs mt-1 text-[#8696a0]">
                    {aiStatus?.message || (aiStatus?.available ? 'Layanan Ollama berjalan di localhost:11434' : 'Layanan Ollama belum aktif')}
                  </p>
                  {aiStatus?.activeModel && (
                    <div className="mt-2 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-md bg-[#202c33] border border-[#2a3942] text-xs font-mono text-[#00a884]">
                      Model aktif: <strong>{aiStatus.activeModel}</strong>
                    </div>
                  )}
                </div>
              </div>
              <button
                onClick={onRefreshAiStatus}
                title="Cek ulang status Ollama"
                className="p-1.5 text-[#8696a0] hover:text-[#e9edef] hover:bg-[#202c33] rounded-lg transition"
              >
                <RefreshCw className="w-4 h-4" />
              </button>
            </div>
          </div>

          {/* System Prompt Form */}
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <label htmlFor="systemPromptInput" className="font-semibold text-xs uppercase tracking-wider text-[#00a884]">
                System Prompt / Karakter AI
              </label>
              <button
                type="button"
                onClick={handleResetDefault}
                className="text-xs text-[#8696a0] hover:text-[#e9edef] underline"
              >
                Kembalikan ke Default
              </button>
            </div>
            <textarea
              id="systemPromptInput"
              rows={5}
              value={systemPrompt}
              onChange={(e) => setSystemPrompt(e.target.value)}
              placeholder="Contoh: Anda adalah asisten customer service ramah yang membantu membalas pesan pelanggan dalam bahasa Indonesia sopan dan ringkas."
              className="w-full bg-[#182229] border border-[#2a3942] focus:border-[#00a884] rounded-2xl p-4 text-xs sm:text-sm text-[#e9edef] placeholder-[#8696a0] focus:outline-none transition leading-relaxed resize-none"
            />
            <p className="text-[11px] text-[#8696a0]">
              System prompt ini akan disimpan ke database SQLite lokal dan digunakan saat menekan tombol "Buat Draf AI".
            </p>
          </div>

          {/* Save Action Status */}
          {saveError && (
            <div className="p-3 bg-red-950/40 border border-red-800 rounded-xl text-xs text-red-300 flex items-center gap-2">
              <AlertTriangle className="w-4 h-4 text-red-400 flex-shrink-0" />
              <span>{saveError}</span>
            </div>
          )}

          {/* Panduan Instalasi & Model Ringan Sesuai RAM */}
          <div className="bg-[#182229] border border-[#222e35] rounded-2xl p-4 space-y-3">
            <h3 className="font-semibold text-xs uppercase tracking-wider text-[#00a884] flex items-center gap-2">
              <Cpu className="w-4 h-4" /> Panduan Model AI Sesuai RAM Komputer
            </h3>
            <p className="text-xs text-[#8696a0] leading-relaxed">
              Ollama berjalan 100% di komputer lokal Anda tanpa biaya API. Pilih model sesuai kapasitas RAM:
            </p>

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-xs">
              <div className="p-3 bg-[#111b21] rounded-xl border border-[#2a3942]">
                <div className="flex items-center gap-2 text-emerald-400 font-semibold mb-1">
                  <HardDrive className="w-3.5 h-3.5" /> RAM 4GB - 8GB (Sangat Ringan)
                </div>
                <p className="text-[#8696a0] mb-2 text-[11px]">Cepat, hemat memori, cocok untuk laptop standar:</p>
                <code className="block bg-[#202c33] p-1.5 rounded text-[11px] text-[#e9edef] font-mono">
                  ollama run qwen2.5:1.5b
                </code>
              </div>

              <div className="p-3 bg-[#111b21] rounded-xl border border-[#2a3942]">
                <div className="flex items-center gap-2 text-cyan-400 font-semibold mb-1">
                  <HardDrive className="w-3.5 h-3.5" /> RAM 8GB - 16GB (Kualitas Tinggi)
                </div>
                <p className="text-[#8696a0] mb-2 text-[11px]">Jawaban lebih cerdas & bahasa sangat natural:</p>
                <code className="block bg-[#202c33] p-1.5 rounded text-[11px] text-[#e9edef] font-mono">
                  ollama run llama3.2
                </code>
              </div>
            </div>

            <div className="text-[11px] text-[#8696a0] flex items-center gap-1.5 pt-1">
              <ShieldCheck className="w-3.5 h-3.5 text-emerald-400 flex-shrink-0" />
              <span>Privasi terjamin: Kredensial dan data WhatsApp tidak pernah dikirim ke pihak luar.</span>
            </div>
          </div>
        </div>

        {/* Modal Footer */}
        <div className="px-6 py-4 bg-[#202c33] border-t border-[#2a3942] flex items-center justify-between flex-shrink-0">
          <div>
            {isSaved && (
              <span className="inline-flex items-center gap-1.5 text-xs text-emerald-400 font-medium">
                <Check className="w-4 h-4" /> Tersimpan!
              </span>
            )}
          </div>
          <div className="flex items-center gap-3">
            <button
              onClick={onClose}
              className="px-4 py-2 text-xs font-medium text-[#aebac1] hover:text-white rounded-xl hover:bg-[#374248] transition"
            >
              Batal
            </button>
            <button
              onClick={handleSave}
              disabled={isLoading}
              className="px-5 py-2 text-xs font-semibold rounded-xl bg-[#00a884] hover:bg-[#02906f] text-white flex items-center gap-2 shadow-lg shadow-[#00a884]/20 transition disabled:opacity-50"
            >
              <Save className="w-4 h-4" />
              <span>{isLoading ? 'Menyimpan...' : 'Simpan Pengaturan'}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
