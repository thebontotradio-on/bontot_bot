import React, { useState, useEffect, useRef, useMemo } from 'react';
import { Send, Bot, Sparkles, Check, CheckCheck, Clock, MessageSquare, AlertCircle } from 'lucide-react';
import api from '../services/api';

function formatMessageTime(timestamp) {
  if (!timestamp) return '';
  const date = new Date(timestamp * 1000);
  return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

export default function ChatArea({
  activeChat,
  messages,
  onSendMessage,
  isSendingMessage,
  aiStatus
}) {
  const [inputText, setInputText] = useState('');
  const [isGeneratingAi, setIsGeneratingAi] = useState(false);
  const [aiError, setAiError] = useState(null);
  const messagesEndRef = useRef(null);
  const textareaRef = useRef(null);

  // FORENSIC AUDIT DEFENSE: Memoize and deduplicate messages by ID to prevent duplicate bubble rendering
  const displayMessages = useMemo(() => {
    if (!Array.isArray(messages)) return [];
    const seen = new Set();
    const result = [];
    for (const m of messages) {
      if (!m || !m.id) continue;
      if (seen.has(m.id)) continue;
      seen.add(m.id);
      result.push(m);
    }
    return result;
  }, [messages]);

  // Auto scroll to bottom
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [displayMessages, isSendingMessage]);

  // Find the latest incoming message in the active thread
  const latestIncomingMessage = [...displayMessages]
    .reverse()
    .find((m) => !m.is_from_me && m.text && m.text.trim().length > 0);

  const canGenerateAiDraft = Boolean(latestIncomingMessage) && !isGeneratingAi;

  const handleGenerateAiDraft = async () => {
    if (!latestIncomingMessage) return;

    setIsGeneratingAi(true);
    setAiError(null);

    try {
      const res = await api.generateAiReply(latestIncomingMessage.text);
      if (res.data?.success && res.data.reply) {
        // Requirement: Insert AI draft into chat input without sending
        setInputText(res.data.reply);
        if (textareaRef.current) {
          textareaRef.current.focus();
        }
      } else {
        setAiError(res.data?.error || 'Gagal menghasilkan balasan AI.');
      }
    } catch (err) {
      const msg = err.response?.data?.error || err.message || 'Gagal terhubung ke service AI Ollama.';
      setAiError(msg);
    } finally {
      setIsGeneratingAi(false);
    }
  };

  const handleSend = (e) => {
    e?.preventDefault();
    if (!inputText.trim() || isSendingMessage) return;

    onSendMessage(inputText.trim());
    setInputText('');
  };

  const handleKeyDown = (e) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  if (!activeChat) {
    return (
      <main className="flex-1 bg-[#0c1317] flex flex-col items-center justify-center p-6 text-center select-none">
        <div className="w-20 h-20 rounded-2xl bg-[#202c33] flex items-center justify-center text-[#8696a0] mb-4 shadow-xl">
          <MessageSquare className="w-10 h-10 text-[#00a884]" />
        </div>
        <h2 className="text-xl font-bold text-[#e9edef] mb-2">WA BONTOT Dashboard</h2>
        <p className="text-sm text-[#8696a0] max-w-md">
          Pilih kontak dari daftar di sebelah kiri untuk melihat percakapan, membaca pesan secara realtime, atau membuat draf balasan dengan AI lokal.
        </p>
      </main>
    );
  }

  const isLid = activeChat.id?.endsWith('@lid');
  const displayName = activeChat.name || activeChat.id;

  return (
    <main className="flex-1 bg-[#0c1317] flex flex-col h-full overflow-hidden">
      {/* Active Chat Header */}
      <div className="h-16 bg-[#202c33] border-b border-[#2a3942] px-4 sm:px-6 flex items-center justify-between flex-shrink-0">
        <div className="flex items-center gap-3 min-w-0">
          <div className="w-10 h-10 rounded-full bg-[#374248] border border-[#41525d] flex items-center justify-center text-[#d1d7db] font-semibold text-base flex-shrink-0">
            {displayName.charAt(0).toUpperCase()}
          </div>
          <div className="min-w-0">
            <h2 className="text-sm font-semibold text-[#e9edef] truncate">
              {displayName}
            </h2>
            <p className="text-xs text-[#8696a0] truncate font-mono">
              {isLid ? 'WhatsApp LID' : activeChat.id}
            </p>
          </div>
        </div>

        {/* Info indicator */}
        <div className="text-right hidden sm:block">
          <span className="text-xs text-[#8696a0]">
            {displayMessages.length} pesan tercatat
          </span>
        </div>
      </div>

      {/* Messages Scroll Area */}
      <div className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-3 bg-[#0b141a]/90 bg-[radial-gradient(#202c33_1px,transparent_1px)] [background-size:16px_16px]">
        {displayMessages.length === 0 ? (
          <div className="flex items-center justify-center h-full">
            <div className="bg-[#182229]/80 border border-[#222e35] rounded-xl p-4 text-center text-xs text-[#8696a0] max-w-sm">
              Belum ada riwayat pesan di chat ini. Tulis pesan di bawah untuk memulai obrolan.
            </div>
          </div>
        ) : (
          displayMessages.map((msg, index) => {
            const isMe = Boolean(msg.is_from_me);

            return (
              <div
                key={msg.id || `msg-${index}`}
                className={`flex ${isMe ? 'justify-end' : 'justify-start'}`}
              >
                <div
                  className={`max-w-[85%] sm:max-w-[70%] md:max-w-[60%] rounded-2xl px-3.5 py-2 text-sm shadow-md transition-all ${
                    isMe
                      ? 'bg-[#005c4b] text-[#e9edef] rounded-tr-xs'
                      : 'bg-[#202c33] text-[#e9edef] rounded-tl-xs'
                  }`}
                >
                  {/* Sender label for incoming */}
                  {!isMe && msg.sender_jid && msg.sender_jid !== activeChat.id && (
                    <div className="text-[11px] font-semibold text-[#00a884] mb-0.5">
                      {msg.sender_jid}
                    </div>
                  )}

                  {/* Message body */}
                  <div className="whitespace-pre-wrap break-words leading-relaxed select-text">
                    {msg.text}
                  </div>

                  {/* Timestamp & Status */}
                  <div className="flex items-center justify-end gap-1 text-[10px] text-[#8696a0] mt-1 select-none">
                    <span>{formatMessageTime(msg.timestamp)}</span>
                    {isMe && (
                      <span>
                        {msg.status === 'sending' ? (
                          <Clock className="w-3 h-3 text-amber-400 animate-pulse" />
                        ) : msg.status === 'delivered' ? (
                          <CheckCheck className="w-3.5 h-3.5 text-[#53bdeb]" />
                        ) : (
                          <Check className="w-3.5 h-3.5 text-[#8696a0]" />
                        )}
                      </span>
                    )}
                  </div>
                </div>
              </div>
            );
          })
        )}
        <div ref={messagesEndRef} />
      </div>

      {/* AI Error Notification Banner */}
      {aiError && (
        <div className="px-4 py-2 bg-red-950/80 border-t border-red-800 text-red-200 text-xs flex items-center justify-between">
          <div className="flex items-center gap-2">
            <AlertCircle className="w-4 h-4 flex-shrink-0 text-red-400" />
            <span>{aiError}</span>
          </div>
          <button
            onClick={() => setAiError(null)}
            className="text-red-300 hover:text-white text-xs underline font-medium ml-2"
          >
            Tutup
          </button>
        </div>
      )}

      {/* Input Bar */}
      <div className="bg-[#202c33] border-t border-[#2a3942] p-3 sm:p-4 flex-shrink-0">
        <form onSubmit={handleSend} className="flex items-end gap-2">
          {/* AI Draft Button */}
          <button
            type="button"
            onClick={handleGenerateAiDraft}
            disabled={!canGenerateAiDraft}
            title={
              !latestIncomingMessage
                ? 'Tidak ada pesan masuk untuk dijawab dengan AI'
                : !aiStatus?.available
                ? 'Ollama lokal offline (klik untuk mencoba atau buka pengaturan)'
                : 'Buat draf balasan otomatis menggunakan AI lokal'
            }
            className={`px-3 py-2.5 rounded-xl text-xs font-semibold flex items-center gap-1.5 transition-all flex-shrink-0 ${
              isGeneratingAi
                ? 'bg-[#00a884]/20 text-[#00a884] border border-[#00a884]/40 cursor-wait'
                : canGenerateAiDraft
                ? 'bg-[#111b21] hover:bg-[#00a884] text-[#00a884] hover:text-white border border-[#00a884]/40 shadow-sm'
                : 'bg-[#111b21] text-[#8696a0]/50 border border-[#2a3942] cursor-not-allowed opacity-50'
            }`}
          >
            {isGeneratingAi ? (
              <>
                <div className="w-3.5 h-3.5 border-2 border-[#00a884] border-t-transparent rounded-full animate-spin" />
                <span className="hidden sm:inline">Menyusun...</span>
              </>
            ) : (
              <>
                <Sparkles className="w-3.5 h-3.5" />
                <span className="hidden sm:inline">Buat Draf AI</span>
                <span className="sm:hidden">Draf AI</span>
              </>
            )}
          </button>

          {/* Text Input */}
          <div className="flex-1 bg-[#2a3942] rounded-xl px-3 py-2 flex items-center focus-within:ring-1 focus-within:ring-[#00a884] transition">
            <textarea
              ref={textareaRef}
              rows={1}
              value={inputText}
              onChange={(e) => setInputText(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Ketik pesan balasan... (Enter kirim, Shift+Enter baris baru)"
              className="w-full bg-transparent text-sm text-[#e9edef] placeholder-[#8696a0] resize-none focus:outline-none max-h-32"
            />
          </div>

          {/* Send Button */}
          <button
            type="submit"
            disabled={!inputText.trim() || isSendingMessage}
            className={`p-2.5 rounded-xl flex-shrink-0 transition-colors shadow-md ${
              inputText.trim() && !isSendingMessage
                ? 'bg-[#00a884] hover:bg-[#02906f] text-white'
                : 'bg-[#2a3942] text-[#8696a0] cursor-not-allowed opacity-50'
            }`}
          >
            <Send className="w-5 h-5" />
          </button>
        </form>
      </div>
    </main>
  );
}
