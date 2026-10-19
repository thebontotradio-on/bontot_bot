import React, { useState, useEffect, useRef, useCallback } from 'react';
import { io } from 'socket.io-client';
import api from './services/api';
import Header from './components/Header';
import Sidebar from './components/Sidebar';
import ChatArea from './components/ChatArea';
import QrScreen from './components/QrScreen';
import AiSettingsModal from './components/AiSettingsModal';
import ConfirmLogoutModal from './components/ConfirmLogoutModal';
import NewChatModal from './components/NewChatModal';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001';

/**
 * Deduplicate an array of messages by ID, preserving order.
 */
function deduplicateMessages(list) {
  if (!Array.isArray(list)) return [];
  const seenIds = new Set();
  const result = [];
  for (const m of list) {
    if (!m || !m.id) continue;
    if (seenIds.has(m.id)) continue;
    seenIds.add(m.id);
    result.push(m);
  }
  return result;
}

export default function App() {
  const [status, setStatus] = useState('connecting'); // 'connecting' | 'qr' | 'connected' | 'closed'
  const [user, setUser] = useState(null);
  const [qrCode, setQrCode] = useState(null);
  const [isRefreshingQr, setIsRefreshingQr] = useState(false);

  const [chats, setChats] = useState([]);
  const [activeChatId, setActiveChatId] = useState(null);
  const [messages, setMessages] = useState([]);
  const [isLoadingChats, setIsLoadingChats] = useState(false);
  const [isSendingMessage, setIsSendingMessage] = useState(false);

  // Auto-Reply & AI states
  const [aiStatus, setAiStatus] = useState(null);
  const [autoReplyEnabled, setAutoReplyEnabled] = useState(false);
  const [isAutoReplyProcessing, setIsAutoReplyProcessing] = useState(false);

  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [isLogoutModalOpen, setIsLogoutModalOpen] = useState(false);
  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [isNewChatModalOpen, setIsNewChatModalOpen] = useState(false);

  const socketRef = useRef(null);
  const activeChatIdRef = useRef(activeChatId);

  useEffect(() => {
    activeChatIdRef.current = activeChatId;
  }, [activeChatId]);

  const loadChats = useCallback(async () => {
    setIsLoadingChats(true);
    try {
      const res = await api.getChats();
      if (res.data?.success && Array.isArray(res.data.chats)) {
        setChats(res.data.chats);
      }
    } catch (err) {
      // Silently handle chat load failure
    } finally {
      setIsLoadingChats(false);
    }
  }, []);

  const refreshAiStatus = useCallback(async () => {
    try {
      const res = await api.getAiStatus();
      setAiStatus(res.data);
    } catch (err) {
      setAiStatus({
        available: false,
        message: 'Tidak dapat menghubungi server backend untuk status AI.'
      });
    }
  }, []);

  const loadAutoReplyStatus = useCallback(async () => {
    try {
      const res = await api.getAutoReplyStatus();
      if (res.data?.success) {
        setAutoReplyEnabled(Boolean(res.data.enabled));
      }
    } catch (err) {}
  }, []);

  // Initialize Socket.IO connection
  useEffect(() => {
    const socketTarget = API_BASE_URL || undefined;
    const socket = io(socketTarget, {
      transports: ['websocket', 'polling']
    });
    socketRef.current = socket;

    socket.on('connect', () => {
      // Socket connected
    });

    socket.on('status_change', (data) => {
      if (data.status) {
        setStatus(data.status);
      }
      if (data.user !== undefined) {
        setUser(data.user);
      }
      if (data.qr !== undefined) {
        setQrCode(data.qr);
      }

      if (data.status === 'connected') {
        loadChats();
        loadAutoReplyStatus();
      }
    });

    // Auto-Reply realtime updates
    socket.on('auto_reply_status', (data) => {
      if (data && data.enabled !== undefined) {
        setAutoReplyEnabled(Boolean(data.enabled));
      }
    });

    socket.on('auto_reply_processing', (data) => {
      if (!data) return;
      if (data.status === 'processing') {
        setIsAutoReplyProcessing(true);
      } else {
        setIsAutoReplyProcessing(false);
      }
    });

    socket.on('new_message', (payload) => {
      const { chatId, message } = payload;
      if (!message || !message.id) return;

      // If incoming message belongs to active chat, update message list with deduplication
      if (activeChatIdRef.current === chatId) {
        setMessages((prev) => {
          // If already in list by confirmed ID, do not add duplicate
          if (prev.some((m) => m.id === message.id)) {
            return prev;
          }

          // If this is an outgoing message that matches a pending optimistic message
          if (message.is_from_me) {
            const optIndex = prev.findIndex(
              (m) =>
                typeof m.id === 'string' &&
                m.id.startsWith('optimistic-') &&
                m.text === message.text
            );

            if (optIndex !== -1) {
              const updated = [...prev];
              updated[optIndex] = message;
              return deduplicateMessages(updated);
            }
          }

          return deduplicateMessages([...prev, message]);
        });
      }

      // Refresh chats list to update last message preview and unread counters
      loadChats();
    });

    socket.on('chat_updated', (updatedChat) => {
      if (!updatedChat || !updatedChat.id) return;
      setChats((prev) => {
        const index = prev.findIndex((c) => c.id === updatedChat.id);
        if (index >= 0) {
          const next = [...prev];
          next[index] = { ...next[index], ...updatedChat };
          return next.sort((a, b) => (b.last_message_timestamp || 0) - (a.last_message_timestamp || 0));
        } else {
          return [updatedChat, ...prev];
        }
      });
    });

    return () => {
      socket.disconnect();
    };
  }, [loadChats, loadAutoReplyStatus]);

  // Check initial status & AI status
  useEffect(() => {
    checkInitialStatus();
    refreshAiStatus();
    loadAutoReplyStatus();
  }, [refreshAiStatus, loadAutoReplyStatus]);

  // Polling every 3 seconds for QR / connection status when not yet connected
  useEffect(() => {
    if (status === 'connected') return;

    const interval = setInterval(async () => {
      try {
        const [statusRes, qrRes] = await Promise.all([
          api.getStatus(),
          api.getQR()
        ]);

        if (statusRes.data?.status) {
          setStatus(statusRes.data.status);
          if (statusRes.data.user) setUser(statusRes.data.user);
        }

        if (qrRes.data?.qr) {
          setQrCode(qrRes.data.qr);
        }

        if (statusRes.data?.status === 'connected') {
          loadChats();
          loadAutoReplyStatus();
        }
      } catch (err) {
        // Server might still be booting up
      }
    }, 3000);

    return () => clearInterval(interval);
  }, [status, loadChats, loadAutoReplyStatus]);

  const checkInitialStatus = async () => {
    try {
      const [statusRes, qrRes] = await Promise.all([
        api.getStatus(),
        api.getQR()
      ]);

      if (statusRes.data?.status) {
        setStatus(statusRes.data.status);
        setUser(statusRes.data.user || null);
      }
      if (qrRes.data?.qr) {
        setQrCode(qrRes.data.qr);
      }

      if (statusRes.data?.status === 'connected') {
        loadChats();
        loadAutoReplyStatus();
      }
    } catch (err) {
      // Backend not yet ready
    }
  };

  const handleToggleAutoReply = async () => {
    try {
      const nextState = !autoReplyEnabled;
      const res = await api.setAutoReplySettings(nextState);
      if (res.data?.success) {
        setAutoReplyEnabled(Boolean(res.data.enabled));
      }
    } catch (err) {
      alert(err.response?.data?.error || 'Gagal mengubah status Auto-Reply.');
    }
  };

  const handleSelectChat = async (chatId) => {
    setActiveChatId(chatId);

    // Optimistically reset unread counter in UI
    setChats((prev) =>
      prev.map((c) => (c.id === chatId ? { ...c, unread_count: 0 } : c))
    );

    try {
      const res = await api.getMessages(chatId);
      if (res.data?.success && Array.isArray(res.data.messages)) {
        setMessages(deduplicateMessages(res.data.messages));
      }
    } catch (err) {
      setMessages([]);
    }
  };

  const handleSendMessage = async (text) => {
    if (!activeChatId || !text.trim() || isSendingMessage) return;

    const tempId = `optimistic-${Date.now()}`;
    const optimisticMessage = {
      id: tempId,
      chat_id: activeChatId,
      sender_jid: user?.id || 'me',
      text: text.trim(),
      is_from_me: 1,
      timestamp: Math.floor(Date.now() / 1000),
      status: 'sending'
    };

    // Optimistic UI update
    setMessages((prev) => deduplicateMessages([...prev, optimisticMessage]));
    setIsSendingMessage(true);

    try {
      const res = await api.sendMessage(activeChatId, text.trim());
      if (res.data?.success && res.data.message) {
        const confirmedMsg = res.data.message;
        setMessages((prev) => {
          // If the message is already present by real ID (due to fast Socket.IO broadcast),
          // simply remove the temporary optimistic item
          const alreadyHasReal = prev.some((m) => m.id === confirmedMsg.id);
          if (alreadyHasReal) {
            return deduplicateMessages(prev.filter((m) => m.id !== tempId));
          }
          // Otherwise, replace the optimistic placeholder
          return deduplicateMessages(
            prev.map((m) => (m.id === tempId ? confirmedMsg : m))
          );
        });
      }
    } catch (err) {
      // Mark as error / revert sending status
      setMessages((prev) =>
        prev.map((m) => (m.id === tempId ? { ...m, status: 'failed' } : m))
      );
    } finally {
      setIsSendingMessage(false);
      loadChats();
    }
  };

  const handleStartNewChat = async (to, text) => {
    setIsSendingMessage(true);
    try {
      const res = await api.sendMessage(to, text);
      if (res.data?.success) {
        const jid = res.data.jid;
        await loadChats();
        handleSelectChat(jid);
      }
    } catch (err) {
      alert(err.response?.data?.error || err.message || 'Gagal mengirim pesan ke nomor tujuan.');
    } finally {
      setIsSendingMessage(false);
    }
  };

  const handleRefreshQr = async () => {
    setIsRefreshingQr(true);
    try {
      await api.resetSession();
      const qrRes = await api.getQR();
      if (qrRes.data?.qr) {
        setQrCode(qrRes.data.qr);
      }
    } catch (err) {
      // Handle error
    } finally {
      setIsRefreshingQr(false);
    }
  };

  const handleLogout = async () => {
    setIsLoggingOut(true);
    try {
      await api.resetSession();
      setStatus('closed');
      setUser(null);
      setQrCode(null);
      setChats([]);
      setActiveChatId(null);
      setMessages([]);
      setIsLogoutModalOpen(false);
    } catch (err) {
      alert(err.response?.data?.error || 'Gagal keluar dari sesi WhatsApp.');
    } finally {
      setIsLoggingOut(false);
    }
  };

  const activeChat = chats.find((c) => c.id === activeChatId) || (activeChatId ? { id: activeChatId, name: activeChatId } : null);

  return (
    <div className="flex flex-col h-screen w-screen overflow-hidden bg-[#0b141a]">
      {/* Top Application Header */}
      <Header
        status={status}
        user={user}
        aiStatus={aiStatus}
        autoReplyEnabled={autoReplyEnabled}
        onToggleAutoReply={handleToggleAutoReply}
        isAutoReplyProcessing={isAutoReplyProcessing}
        onOpenSettings={() => setIsSettingsOpen(true)}
        onOpenLogout={() => setIsLogoutModalOpen(true)}
      />

      {/* Main Body: QR Screen or Inbox Dashboard */}
      {status !== 'connected' ? (
        <QrScreen
          status={status}
          qrCode={qrCode}
          onRefresh={handleRefreshQr}
          isRefreshing={isRefreshingQr}
        />
      ) : (
        <div className="flex-1 flex overflow-hidden">
          {/* Left Chat List Sidebar */}
          <Sidebar
            chats={chats}
            activeChatId={activeChatId}
            onSelectChat={handleSelectChat}
            onOpenNewChat={() => setIsNewChatModalOpen(true)}
            isLoading={isLoadingChats}
          />

          {/* Central Conversation Panel */}
          <ChatArea
            activeChat={activeChat}
            messages={messages}
            onSendMessage={handleSendMessage}
            isSendingMessage={isSendingMessage}
            aiStatus={aiStatus}
          />
        </div>
      )}

      {/* AI Settings Modal */}
      <AiSettingsModal
        isOpen={isSettingsOpen}
        onClose={() => setIsSettingsOpen(false)}
        aiStatus={aiStatus}
        onRefreshAiStatus={refreshAiStatus}
      />

      {/* Logout Confirmation Modal */}
      <ConfirmLogoutModal
        isOpen={isLogoutModalOpen}
        onClose={() => setIsLogoutModalOpen(false)}
        onConfirm={handleLogout}
        isLoggingOut={isLoggingOut}
      />

      {/* New Direct Chat Modal */}
      <NewChatModal
        isOpen={isNewChatModalOpen}
        onClose={() => setIsNewChatModalOpen(false)}
        onStartChat={handleStartNewChat}
      />
    </div>
  );
}
