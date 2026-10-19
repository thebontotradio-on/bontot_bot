import React, { useState } from 'react';
import { Search, Plus, MessageCircle, User, Users } from 'lucide-react';

function formatTimestamp(timestamp) {
  if (!timestamp) return '';
  const date = new Date(timestamp * 1000);
  const now = new Date();
  
  const isToday =
    date.getDate() === now.getDate() &&
    date.getMonth() === now.getMonth() &&
    date.getFullYear() === now.getFullYear();

  if (isToday) {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  }

  return date.toLocaleDateString([], { day: 'numeric', month: 'short' });
}

export default function Sidebar({
  chats,
  activeChatId,
  onSelectChat,
  onOpenNewChat,
  isLoading
}) {
  const [searchQuery, setSearchQuery] = useState('');

  const filteredChats = chats.filter((chat) => {
    const q = searchQuery.toLowerCase();
    const nameMatch = (chat.name || '').toLowerCase().includes(q);
    const jidMatch = (chat.id || '').toLowerCase().includes(q);
    const textMatch = (chat.last_message_text || '').toLowerCase().includes(q);
    return nameMatch || jidMatch || textMatch;
  });

  return (
    <aside className="w-80 md:w-96 bg-[#111b21] border-r border-[#222e35] flex flex-col h-full flex-shrink-0 select-none">
      {/* Top search & new chat bar */}
      <div className="p-3 bg-[#111b21] border-b border-[#222e35] flex items-center gap-2">
        <div className="relative flex-1">
          <Search className="w-4 h-4 text-[#8696a0] absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Cari atau mulai chat baru"
            className="w-full bg-[#202c33] text-[#e9edef] placeholder-[#8696a0] text-sm pl-9 pr-3 py-1.5 rounded-lg focus:outline-none focus:ring-1 focus:ring-[#00a884] transition"
          />
        </div>
        <button
          onClick={onOpenNewChat}
          title="Kirim pesan ke nomor baru"
          className="p-2 bg-[#202c33] hover:bg-[#00a884] text-[#aebac1] hover:text-white rounded-lg transition-colors flex-shrink-0"
        >
          <Plus className="w-4 h-4" />
        </button>
      </div>

      {/* Chat list */}
      <div className="flex-1 overflow-y-auto">
        {isLoading && chats.length === 0 ? (
          <div className="p-6 text-center text-sm text-[#8696a0] flex flex-col items-center justify-center gap-2">
            <div className="w-6 h-6 border-2 border-[#00a884] border-t-transparent rounded-full animate-spin" />
            <span>Memuat daftar percakapan...</span>
          </div>
        ) : filteredChats.length === 0 ? (
          <div className="p-8 text-center text-sm text-[#8696a0]">
            <MessageCircle className="w-10 h-10 mx-auto mb-2 text-[#3b4a54] stroke-1" />
            {searchQuery ? (
              <p>Tidak ada chat yang sesuai dengan pencarian "{searchQuery}"</p>
            ) : (
              <div>
                <p className="font-medium text-[#d1d7db]">Belum ada riwayat chat</p>
                <p className="text-xs mt-1 text-[#8696a0]">Pesan masuk otomatis akan muncul di sini atau klik tanda (+) di atas untuk memulai percakapan baru.</p>
              </div>
            )}
          </div>
        ) : (
          <ul className="divide-y divide-[#202c33]/50">
            {filteredChats.map((chat) => {
              const isActive = chat.id === activeChatId;
              const isGroup = chat.id.endsWith('@g.us');
              const initial = (chat.name || chat.id || '?').charAt(0).toUpperCase();

              return (
                <li key={chat.id}>
                  <button
                    onClick={() => onSelectChat(chat.id)}
                    className={`w-full text-left px-4 py-3 flex items-center gap-3 transition-colors ${
                      isActive
                        ? 'bg-[#2a3942]'
                        : 'hover:bg-[#202c33]'
                    }`}
                  >
                    {/* Avatar */}
                    <div className="w-12 h-12 rounded-full bg-[#374248] flex items-center justify-center text-[#d1d7db] font-semibold text-base flex-shrink-0 border border-[#41525d]">
                      {isGroup ? (
                        <Users className="w-5 h-5 text-[#8696a0]" />
                      ) : (
                        <span>{initial}</span>
                      )}
                    </div>

                    {/* Chat Info */}
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center justify-between gap-1 mb-1">
                        <span className="font-medium text-sm text-[#e9edef] truncate">
                          {chat.name || chat.id}
                        </span>
                        <span className="text-[11px] text-[#8696a0] flex-shrink-0">
                          {formatTimestamp(chat.last_message_timestamp)}
                        </span>
                      </div>

                      <div className="flex items-center justify-between gap-2">
                        <p className="text-xs text-[#8696a0] truncate flex-1">
                          {chat.last_message_text || 'Tidak ada pesan teks'}
                        </p>
                        {chat.unread_count > 0 && (
                          <span className="inline-flex items-center justify-center min-w-[20px] h-5 px-1.5 rounded-full bg-[#00a884] text-[#111b21] font-bold text-[11px] flex-shrink-0">
                            {chat.unread_count}
                          </span>
                        )}
                      </div>
                    </div>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </aside>
  );
}
