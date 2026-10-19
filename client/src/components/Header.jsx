import React from 'react';
import { Settings, LogOut, Bot, Sparkles, MessageSquare, Zap, ZapOff, AlertCircle } from 'lucide-react';

export default function Header({
  status,
  user,
  aiStatus,
  autoReplyEnabled,
  onToggleAutoReply,
  isAutoReplyProcessing,
  onOpenSettings,
  onOpenLogout
}) {
  const isConnected = status === 'connected';
  const isAiAvailable = Boolean(aiStatus?.available);

  return (
    <header className="h-16 bg-[#202c33] border-b border-[#2a3942] px-3 sm:px-6 flex items-center justify-between flex-shrink-0 select-none">
      {/* Brand & Connection Status */}
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-[#00a884] to-[#25d366] flex items-center justify-center shadow-lg shadow-[#00a884]/20 flex-shrink-0">
          <MessageSquare className="w-5 h-5 text-white" />
        </div>
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <h1 className="text-base font-bold text-[#e9edef] tracking-wide truncate">WA BONTOT</h1>
            <span
              className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium flex-shrink-0 ${
                isConnected
                  ? 'bg-emerald-500/15 text-emerald-400 border border-emerald-500/30'
                  : 'bg-amber-500/15 text-amber-400 border border-amber-500/30'
              }`}
            >
              <span className={`w-1.5 h-1.5 rounded-full ${isConnected ? 'bg-emerald-400 animate-pulse' : 'bg-amber-400'}`} />
              {isConnected ? 'Terhubung' : status === 'qr' ? 'Scan QR' : 'Menghubungkan'}
            </span>
          </div>
          {user && (
            <p className="text-xs text-[#8696a0] truncate max-w-[150px] sm:max-w-[260px]">
              {user.name}
            </p>
          )}
        </div>
      </div>

      {/* Action Badges, SI BONTOT Auto-Reply Controls & Buttons */}
      <div className="flex items-center gap-2 sm:gap-3">
        {/* SI BONTOT Active Processing Indicator */}
        {isAutoReplyProcessing && (
          <div className="hidden lg:flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-[#00a884]/15 border border-[#00a884]/30 text-[#00a884] text-xs font-medium animate-pulse">
            <Sparkles className="w-3.5 h-3.5 animate-spin" />
            <span>SI BONTOT membalas...</span>
          </div>
        )}

        {/* SI BONTOT Auto-Reply Toggle Control */}
        {isConnected && (
          <div className="flex items-center">
            {!isAiAvailable ? (
              <button
                onClick={onOpenSettings}
                title="Ollama tidak tersedia. Klik untuk panduan instalasi & model AI"
                className="flex items-center gap-1.5 px-2.5 sm:px-3 py-1.5 rounded-xl text-xs font-semibold bg-[#111b21] text-amber-400/90 border border-amber-500/30 hover:bg-[#182229] transition"
              >
                <ZapOff className="w-3.5 h-3.5 flex-shrink-0" />
                <span className="hidden sm:inline">Auto-Reply:</span>
                <span className="text-amber-400">AI Offline</span>
              </button>
            ) : (
              <button
                onClick={onToggleAutoReply}
                title={autoReplyEnabled ? 'Klik untuk mematikan SI BONTOT Auto-Reply' : 'Klik untuk mengaktifkan SI BONTOT Auto-Reply'}
                className={`flex items-center gap-2 px-3 py-1.5 rounded-xl text-xs font-semibold transition-all duration-200 border shadow-sm ${
                  autoReplyEnabled
                    ? 'bg-emerald-950/40 text-emerald-300 border-emerald-500/50 hover:bg-emerald-900/40 ring-1 ring-emerald-500/30'
                    : 'bg-[#111b21] text-[#8696a0] border-[#2a3942] hover:bg-[#202c33] hover:text-[#d1d7db]'
                }`}
              >
                <Zap className={`w-3.5 h-3.5 flex-shrink-0 ${autoReplyEnabled ? 'text-emerald-400 animate-pulse' : 'text-[#8696a0]'}`} />
                <span>Auto-Reply:</span>
                <span className={`px-1.5 py-0.5 rounded text-[10px] font-bold tracking-wider uppercase ${
                  autoReplyEnabled ? 'bg-emerald-500 text-[#0c1317]' : 'bg-[#2a3942] text-[#8696a0]'
                }`}>
                  {autoReplyEnabled ? 'ON' : 'OFF'}
                </span>
              </button>
            )}
          </div>
        )}

        {/* AI Status Badge */}
        <button
          onClick={onOpenSettings}
          title="Klik untuk membuka pengaturan AI & System Prompt"
          className={`flex items-center gap-1.5 sm:gap-2 px-2.5 sm:px-3 py-1.5 rounded-xl text-xs font-medium transition-all duration-200 border ${
            isAiAvailable
              ? 'bg-[#111b21] hover:bg-[#222e35] text-[#00a884] border-[#00a884]/30'
              : 'bg-[#111b21] hover:bg-[#222e35] text-[#8696a0] border-[#2a3942]'
          }`}
        >
          <Bot className="w-3.5 h-3.5 flex-shrink-0" />
          <span className="hidden xl:inline">
            {isAiAvailable ? `Ollama (${aiStatus.activeModel || 'Model Aktif'})` : 'Ollama Offline'}
          </span>
          <span className="xl:hidden hidden sm:inline">
            {isAiAvailable ? 'AI Siap' : 'AI Offline'}
          </span>
          <span className={`w-2 h-2 rounded-full ${isAiAvailable ? 'bg-emerald-400 animate-ping' : 'bg-amber-500'}`} />
        </button>

        {/* Settings Button */}
        <button
          onClick={onOpenSettings}
          title="Pengaturan AI & Karakter Prompt"
          className="p-2 text-[#aebac1] hover:text-[#e9edef] hover:bg-[#374248] rounded-xl transition-colors"
        >
          <Settings className="w-5 h-5" />
        </button>

        {/* Logout Button */}
        {isConnected && (
          <button
            onClick={onOpenLogout}
            title="Keluar / Putus Sesi WhatsApp"
            className="p-2 text-[#ef4444] hover:bg-[#ef4444]/15 rounded-xl transition-colors flex items-center gap-1 text-xs font-medium"
          >
            <LogOut className="w-4 h-4" />
            <span className="hidden md:inline">Keluar</span>
          </button>
        )}
      </div>
    </header>
  );
}
