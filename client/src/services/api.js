import axios from 'axios';

const API_BASE_URL = import.meta.env.VITE_API_BASE_URL || 'http://localhost:3001';

export const apiClient = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json'
  },
  timeout: 45000
});

export const api = {
  // WhatsApp endpoints
  getStatus: () => apiClient.get('/api/status'),
  getQR: () => apiClient.get('/api/qr'),
  getChats: () => apiClient.get('/api/chats'),
  getMessages: (chatId) => apiClient.get(`/api/messages?chatId=${encodeURIComponent(chatId)}`),
  sendMessage: (to, message) => apiClient.post('/api/send-message', { to, message }),
  resetSession: () => apiClient.post('/api/reset-session'),

  // AI & Settings endpoints
  getAiStatus: () => apiClient.get('/api/ai/status'),
  generateAiReply: (message, systemPrompt) => apiClient.post('/api/ai-reply', { message, systemPrompt }),
  getSystemPrompt: () => apiClient.get('/api/settings/system-prompt'),
  setSystemPrompt: (systemPrompt) => apiClient.post('/api/settings/system-prompt', { systemPrompt }),

  // SI BONTOT Auto-Reply endpoints
  getAutoReplyStatus: () => apiClient.get('/api/auto-reply/status'),
  setAutoReplySettings: (enabled) => apiClient.post('/api/auto-reply/settings', { enabled })
};

export default api;
