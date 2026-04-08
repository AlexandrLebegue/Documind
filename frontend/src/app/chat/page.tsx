'use client';

import { useState, useEffect, useRef, useCallback } from 'react';
import {
  sendChatMessage,
  streamAgentMessage,
  getChatHistory,
  getChatSessions,
  createChatSession,
  updateChatSession,
  deleteChatSession,
} from '@/lib/api';
import type { ChatMessage as ChatMessageType, ChatSession, ToolCallLog } from '@/lib/api';
import ChatMessage from '@/components/ChatMessage';

const TOOL_LABELS: Record<string, string> = {
  recherche_web: 'Recherche web',
  scraper_page: 'Lecture de page',
  verifier_liens: 'Vérification de liens',
  crawler_procedures: 'Crawl de site',
  creer_procedure: 'Création de procédure',
};

function toolHint(tool: string, args: Record<string, unknown>): string | undefined {
  switch (tool) {
    case 'recherche_web': return args.query as string;
    case 'scraper_page': return args.url as string;
    case 'verifier_liens': return `${(args.urls as string[])?.length ?? 0} lien(s)`;
    case 'crawler_procedures': return args.url_base as string;
    case 'creer_procedure': return (args.name as string) || (args.description as string);
    default: return undefined;
  }
}

const TOOL_ICONS: Record<string, React.ReactNode> = {
  recherche_web: (
    <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="6" cy="6" r="4" /><path d="M10 10L13 13" />
    </svg>
  ),
  scraper_page: (
    <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 2H8L11 5V12H3V2Z" /><path d="M8 2V5H11" /><path d="M5 7H9" /><path d="M5 9H8" />
    </svg>
  ),
  verifier_liens: (
    <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M5.5 8.5a3.5 3.5 0 0 0 5 0l2-2a3.5 3.5 0 0 0-5-5L6 3" /><path d="M8.5 5.5a3.5 3.5 0 0 0-5 0l-2 2a3.5 3.5 0 0 0 5 5L8 11" />
    </svg>
  ),
  crawler_procedures: (
    <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="7" cy="7" r="5.5" /><path d="M7 1.5C7 1.5 5 4 5 7s2 5.5 2 5.5" /><path d="M7 1.5C7 1.5 9 4 9 7s-2 5.5-2 5.5" /><path d="M1.5 7h11" />
    </svg>
  ),
  creer_procedure: (
    <svg width="11" height="11" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M7 2V12" /><path d="M2 7H12" />
    </svg>
  ),
};

export default function ChatPage() {
  // Sessions state
  const [sessions, setSessions] = useState<ChatSession[]>([]);
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null);
  const [sessionsLoading, setSessionsLoading] = useState(true);
  const [sidebarOpen, setSidebarOpen] = useState(false);

  // Messages state
  const [messages, setMessages] = useState<ChatMessageType[]>([]);
  const [input, setInput] = useState('');
  const [sending, setSending] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Agent mode
  const [agentMode, setAgentMode] = useState(false);

  // Live tool calls while agent is running
  const [liveTools, setLiveTools] = useState<{ tool: string; done: boolean; hint?: string }[]>([]);
  const cancelStreamRef = useRef<(() => void) | null>(null);

  // Rename state
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState('');
  const renameInputRef = useRef<HTMLInputElement>(null);

  const messagesEndRef = useRef<HTMLDivElement>(null);
  const textareaRef = useRef<HTMLTextAreaElement>(null);

  // Load sessions on mount
  useEffect(() => {
    async function loadSessions() {
      try {
        const res = await getChatSessions(100, 0);
        setSessions(res.sessions || []);
        // Auto-select the most recent session
        if (res.sessions && res.sessions.length > 0) {
          setActiveSessionId(res.sessions[0].id);
        }
      } catch (err) {
        console.error('Failed to load chat sessions:', err);
      } finally {
        setSessionsLoading(false);
      }
    }
    loadSessions();
  }, []);

  // Load messages when active session changes
  const loadMessages = useCallback(async (sessionId: string) => {
    setLoading(true);
    setError(null);
    try {
      const res = await getChatHistory(sessionId, 100, 0);
      setMessages(res.messages || []);
    } catch (err) {
      console.error('Failed to load chat history:', err);
      setMessages([]);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (activeSessionId) {
      loadMessages(activeSessionId);
    } else {
      setMessages([]);
    }
  }, [activeSessionId, loadMessages]);

  // Auto-scroll on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages]);

  // Focus rename input when editing
  useEffect(() => {
    if (renamingId && renameInputRef.current) {
      renameInputRef.current.focus();
      renameInputRef.current.select();
    }
  }, [renamingId]);

  // ── Handlers ────────────────────────────────────────────────────────────

  const handleNewConversation = () => {
    // Deselect current session to show empty state
    // The session will be created when the first message is sent
    setActiveSessionId(null);
    setMessages([]);
    setInput('');
    setError(null);
    setSidebarOpen(false);
  };

  const handleSelectSession = (sessionId: string) => {
    if (sessionId === activeSessionId) return;
    setActiveSessionId(sessionId);
    setSidebarOpen(false);
  };

  const handleDeleteSession = async (sessionId: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!confirm('Supprimer cette conversation ?')) return;
    try {
      await deleteChatSession(sessionId);
      setSessions((prev) => prev.filter((s) => s.id !== sessionId));
      if (activeSessionId === sessionId) {
        // Switch to next session or empty state
        setSessions((prev) => {
          const remaining = prev.filter((s) => s.id !== sessionId);
          if (remaining.length > 0) {
            setActiveSessionId(remaining[0].id);
          } else {
            setActiveSessionId(null);
          }
          return remaining;
        });
      }
    } catch (err) {
      console.error('Failed to delete session:', err);
    }
  };

  const handleStartRename = (session: ChatSession, e: React.MouseEvent) => {
    e.stopPropagation();
    setRenamingId(session.id);
    setRenameValue(session.title);
  };

  const handleFinishRename = async () => {
    if (!renamingId || !renameValue.trim()) {
      setRenamingId(null);
      return;
    }
    try {
      const updated = await updateChatSession(renamingId, renameValue.trim());
      setSessions((prev) =>
        prev.map((s) => (s.id === updated.id ? updated : s)),
      );
    } catch (err) {
      console.error('Failed to rename session:', err);
    }
    setRenamingId(null);
  };

  const handleSend = async () => {
    const trimmed = input.trim();
    if (!trimmed || sending) return;

    const userMessage: ChatMessageType = {
      id: `temp-${Date.now()}`,
      message: trimmed,
      role: 'user',
      created_at: new Date().toISOString(),
    };

    setMessages((prev) => [...prev, userMessage]);
    setInput('');
    setSending(true);
    setError(null);

    // Reset textarea height
    if (textareaRef.current) {
      textareaRef.current.style.height = 'auto';
    }

    if (agentMode) {
      // ── Agent mode: SSE streaming ──────────────────────────────────────
      setLiveTools([]);

      const finalize = (sessionId: string, toolCallsLog: ToolCallLog[], replyText: string) => {
        const assistantMessage: ChatMessageType = {
          id: `temp-${Date.now()}-reply`,
          message: replyText,
          role: 'assistant',
          tool_calls: toolCallsLog.length > 0 ? toolCallsLog : undefined,
          created_at: new Date().toISOString(),
        };
        setMessages((prev) => [...prev, assistantMessage]);
        setLiveTools([]);
        setSending(false);

        if (!activeSessionId && sessionId) {
          setActiveSessionId(sessionId);
          getChatSessions(100, 0).then((r) => setSessions(r.sessions || [])).catch(() => {
            setSessions((prev) => [{
              id: sessionId,
              title: trimmed.slice(0, 50) + (trimmed.length > 50 ? '…' : ''),
              created_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            }, ...prev]);
          });
        } else {
          setSessions((prev) =>
            prev
              .map((s) => s.id === sessionId ? { ...s, updated_at: new Date().toISOString() } : s)
              .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()),
          );
        }
      };

      const cancel = streamAgentMessage(
        trimmed,
        activeSessionId || undefined,
        (event) => {
          if (event.type === 'tool_start') {
            setLiveTools((prev) => [...prev, { tool: event.tool, done: false, hint: toolHint(event.tool, event.args) }]);
          } else if (event.type === 'tool_done') {
            setLiveTools((prev) =>
              prev.map((t, i) =>
                i === prev.findLastIndex((x) => x.tool === event.tool && !x.done)
                  ? { ...t, done: true }
                  : t,
              ),
            );
          } else if (event.type === 'done') {
            finalize(event.session_id, event.tool_calls_log, event.reply);
          } else if (event.type === 'error') {
            setError(event.message);
            setMessages((prev) => prev.filter((m) => m.id !== userMessage.id));
            setInput(trimmed);
            setLiveTools([]);
            setSending(false);
          }
        },
      );
      cancelStreamRef.current = cancel;

    } else {
      // ── RAG mode: regular fetch ────────────────────────────────────────
      try {
        const res = await sendChatMessage(trimmed, activeSessionId || undefined);
        const assistantMessage: ChatMessageType = {
          id: `temp-${Date.now()}-reply`,
          message: res.reply,
          role: 'assistant',
          context_doc_ids: res.source_document_ids?.length > 0 ? res.source_document_ids : undefined,
          created_at: new Date().toISOString(),
        };
        setMessages((prev) => [...prev, assistantMessage]);

        if (!activeSessionId && res.session_id) {
          setActiveSessionId(res.session_id);
          try {
            const sessRes = await getChatSessions(100, 0);
            setSessions(sessRes.sessions || []);
          } catch {
            setSessions((prev) => [{
              id: res.session_id,
              title: trimmed.slice(0, 50) + (trimmed.length > 50 ? '…' : ''),
              created_at: new Date().toISOString(),
              updated_at: new Date().toISOString(),
            }, ...prev]);
          }
        } else {
          setSessions((prev) =>
            prev
              .map((s) => s.id === res.session_id ? { ...s, updated_at: new Date().toISOString() } : s)
              .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime()),
          );
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : "Erreur lors de l'envoi du message");
        setMessages((prev) => prev.filter((m) => m.id !== userMessage.id));
        setInput(trimmed);
      } finally {
        setSending(false);
      }
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSend();
    }
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    setInput(e.target.value);
    e.target.style.height = 'auto';
    e.target.style.height = Math.min(e.target.scrollHeight, 120) + 'px';
  };

  // ── Active session info ─────────────────────────────────────────────────

  const activeSession = sessions.find((s) => s.id === activeSessionId) || null;

  // ── Render ──────────────────────────────────────────────────────────────

  return (
    <div className="flex h-[calc(100vh-3.5rem)] md:h-screen">
      {/* ── Sessions sidebar ─────────────────────────────────────────── */}

      {/* Mobile overlay */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 bg-black/30 z-30 md:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      <aside
        className={`fixed md:relative z-40 md:z-auto w-72 md:w-64 h-full bg-beige-100 border-r border-beige-300 flex flex-col transform transition-transform duration-300 ease-in-out ${
          sidebarOpen ? 'translate-x-0' : '-translate-x-full'
        } md:translate-x-0`}
      >
        {/* Sidebar header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-beige-300">
          <span className="text-sm font-semibold text-[#1a1a1a]">
            Conversations
          </span>
          <button
            onClick={handleNewConversation}
            className="p-1.5 rounded-lg bg-accent hover:bg-accent-hover text-white transition-colors"
            title="Nouvelle conversation"
          >
            <svg
              width="16"
              height="16"
              viewBox="0 0 16 16"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
            >
              <path d="M8 3V13" />
              <path d="M3 8H13" />
            </svg>
          </button>
        </div>

        {/* Sessions list */}
        <div className="flex-1 overflow-auto py-2 px-2 space-y-0.5">
          {sessionsLoading ? (
            <div className="space-y-2 px-2 py-2">
              {[...Array(4)].map((_, i) => (
                <div key={i} className="skeleton h-10 rounded-lg" />
              ))}
            </div>
          ) : sessions.length === 0 ? (
            <div className="px-3 py-6 text-center">
              <p className="text-xs text-[#6b7280]">Aucune conversation</p>
            </div>
          ) : (
            sessions.map((session) => (
              <div
                key={session.id}
                onClick={() => handleSelectSession(session.id)}
                className={`group flex items-center gap-2 px-3 py-2.5 rounded-lg cursor-pointer transition-colors text-sm ${
                  session.id === activeSessionId
                    ? 'bg-accent/10 text-accent font-medium border border-accent/20'
                    : 'text-[#1a1a1a] hover:bg-beige-200/70'
                }`}
              >
                {/* Chat icon */}
                <svg
                  className="flex-shrink-0 w-4 h-4 opacity-50"
                  viewBox="0 0 16 16"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="1.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M3 3H13C13.5 3 14 3.5 14 4V10C14 10.5 13.5 11 13 11H9L6 14V11H3C2.5 11 2 10.5 2 10V4C2 3.5 2.5 3 3 3Z" />
                </svg>

                {/* Title — editable when renaming */}
                {renamingId === session.id ? (
                  <input
                    ref={renameInputRef}
                    value={renameValue}
                    onChange={(e) => setRenameValue(e.target.value)}
                    onBlur={handleFinishRename}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter') handleFinishRename();
                      if (e.key === 'Escape') setRenamingId(null);
                    }}
                    onClick={(e) => e.stopPropagation()}
                    className="flex-1 min-w-0 px-1 py-0.5 text-sm bg-white border border-accent/30 rounded outline-none focus:ring-1 focus:ring-accent/50"
                  />
                ) : (
                  <span className="flex-1 truncate">{session.title}</span>
                )}

                {/* Action buttons — visible on hover */}
                {renamingId !== session.id && (
                  <div className="flex-shrink-0 flex gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                    <button
                      onClick={(e) => handleStartRename(session, e)}
                      className="p-1 rounded hover:bg-beige-300/60 text-[#6b7280] hover:text-[#1a1a1a] transition-colors"
                      title="Renommer"
                    >
                      <svg
                        width="12"
                        height="12"
                        viewBox="0 0 12 12"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="1.5"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <path d="M7.5 2L10 4.5L4 10.5H1.5V8L7.5 2Z" />
                      </svg>
                    </button>
                    <button
                      onClick={(e) => handleDeleteSession(session.id, e)}
                      className="p-1 rounded hover:bg-red-100 text-[#6b7280] hover:text-red-600 transition-colors"
                      title="Supprimer"
                    >
                      <svg
                        width="12"
                        height="12"
                        viewBox="0 0 12 12"
                        fill="none"
                        stroke="currentColor"
                        strokeWidth="1.5"
                        strokeLinecap="round"
                        strokeLinejoin="round"
                      >
                        <path d="M2 3H10" />
                        <path d="M3 3V10C3 10.5 3.5 11 4 11H8C8.5 11 9 10.5 9 10V3" />
                        <path d="M5 1H7" />
                      </svg>
                    </button>
                  </div>
                )}
              </div>
            ))
          )}
        </div>
      </aside>

      {/* ── Main chat area ───────────────────────────────────────────── */}
      <div className="flex-1 flex flex-col min-w-0">
        {/* Header */}
        <div className="flex-shrink-0 px-4 md:px-6 py-3 border-b border-beige-300 bg-white/50 backdrop-blur-sm flex items-center gap-3">
          {/* Mobile sidebar toggle */}
          <button
            onClick={() => setSidebarOpen(true)}
            className="p-1.5 rounded-lg text-[#6b7280] hover:text-[#1a1a1a] hover:bg-beige-200 transition-colors md:hidden"
            aria-label="Ouvrir les conversations"
          >
            <svg
              width="20"
              height="20"
              viewBox="0 0 20 20"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
            >
              <path d="M3 5H17" />
              <path d="M3 10H17" />
              <path d="M3 15H17" />
            </svg>
          </button>

          <div className="flex-1 min-w-0">
            <h1 className="text-base font-bold text-[#1a1a1a] flex items-center gap-2 truncate">
              <svg
                className="flex-shrink-0"
                width="18"
                height="18"
                viewBox="0 0 20 20"
                fill="none"
                stroke="#2E75B6"
                strokeWidth="1.8"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M4 4H16C17 4 17 5 17 5V13C17 14 16 14 16 14H11L7 17V14H4C3 14 3 13 3 13V5C3 4 4 4 4 4Z" />
              </svg>
              <span className="truncate">
                {activeSession ? activeSession.title : 'Nouvelle conversation'}
              </span>
            </h1>
          </div>

          {/* New conversation button (desktop) */}
          <button
            onClick={handleNewConversation}
            className="hidden md:flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-beige-200 hover:bg-beige-300 text-[#1a1a1a] rounded-lg transition-colors"
          >
            <svg
              width="14"
              height="14"
              viewBox="0 0 14 14"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
            >
              <path d="M7 2V12" />
              <path d="M2 7H12" />
            </svg>
            Nouveau
          </button>
        </div>

        {/* Messages area */}
        <div className="flex-1 overflow-auto px-4 md:px-6 py-4">
          {loading ? (
            <div className="space-y-4">
              {[...Array(3)].map((_, i) => (
                <div
                  key={i}
                  className={`flex ${i % 2 === 0 ? 'justify-end' : 'justify-start'}`}
                >
                  <div
                    className={`skeleton h-16 rounded-2xl ${i % 2 === 0 ? 'w-1/3' : 'w-1/2'}`}
                  />
                </div>
              ))}
            </div>
          ) : messages.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-full text-center">
              <div className="w-20 h-20 bg-beige-200 rounded-full flex items-center justify-center mb-4">
                <svg
                  width="36"
                  height="36"
                  viewBox="0 0 36 36"
                  fill="none"
                  stroke="#6b7280"
                  strokeWidth="1.5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M6 6H30C31.5 6 31.5 7.5 31.5 7.5V22.5C31.5 24 30 24 30 24H19.5L12 30V24H6C4.5 24 4.5 22.5 4.5 22.5V7.5C4.5 6 6 6 6 6Z" />
                  <path d="M12 13.5H24" />
                  <path d="M12 18H20" />
                </svg>
              </div>
              <p className="text-[#1a1a1a] font-medium text-lg mb-1">
                {activeSession
                  ? 'Continuez la conversation'
                  : 'Commencez une nouvelle conversation'}
              </p>
              <p className="text-sm text-[#6b7280] max-w-md">
                L&apos;assistant analysera vos documents pour vous apporter des
                réponses précises et sourcées.
              </p>
              <div className="mt-6 flex flex-wrap gap-2 max-w-md justify-center">
                {(agentMode
                  ? [
                      'Crée une procédure pour renouveler un passeport',
                      'Recherche les démarches pour ouvrir un compte bancaire',
                      'Vérifie si les liens de ma procédure sont valides',
                    ]
                  : [
                      'Quels sont mes documents récents ?',
                      'Quel est le montant total de mes factures ?',
                      'Résume mon dernier contrat',
                    ]
                ).map((suggestion) => (
                  <button
                    key={suggestion}
                    onClick={() => {
                      setInput(suggestion);
                      textareaRef.current?.focus();
                    }}
                    className="px-3 py-1.5 text-xs bg-white border border-beige-300 rounded-full hover:bg-beige-50 hover:border-accent/30 text-[#6b7280] hover:text-[#1a1a1a] transition-colors"
                  >
                    {suggestion}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            <>
              {messages.map((msg) => (
                <ChatMessage key={msg.id} message={msg} />
              ))}
              {/* Sending indicator */}
              {sending && (
                <div className="flex justify-start mb-4">
                  <div className="flex items-end gap-2">
                    <div className="w-7 h-7 rounded-full bg-beige-200 flex items-center justify-center text-xs font-bold text-[#6b7280]">
                      D
                    </div>
                    <div className="px-4 py-3 bg-white border border-beige-300/50 rounded-2xl rounded-bl-md shadow-sm">
                      {liveTools.length === 0 ? (
                        <div className="flex gap-1">
                          <span className="w-2 h-2 bg-[#6b7280] rounded-full animate-bounce" style={{ animationDelay: '0ms' }} />
                          <span className="w-2 h-2 bg-[#6b7280] rounded-full animate-bounce" style={{ animationDelay: '150ms' }} />
                          <span className="w-2 h-2 bg-[#6b7280] rounded-full animate-bounce" style={{ animationDelay: '300ms' }} />
                        </div>
                      ) : (
                        <div className="space-y-2 min-w-[200px] max-w-[300px]">
                          {liveTools.map((t, i) => (
                            <div key={i} className="flex items-start gap-2 text-xs">
                              {/* Status icon */}
                              <div className="flex-shrink-0 mt-0.5">
                                {t.done ? (
                                  <svg className="w-3.5 h-3.5 text-green-500" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                                    <path d="M2.5 7L5.5 10L11.5 4" />
                                  </svg>
                                ) : (
                                  <span className="block w-3.5 h-3.5 border-2 border-accent/40 border-t-accent rounded-full animate-spin" />
                                )}
                              </div>
                              <div className="min-w-0">
                                {/* Tool name + icon */}
                                <div className={`flex items-center gap-1 ${t.done ? 'text-[#6b7280]' : 'text-[#1a1a1a] font-medium'}`}>
                                  <span className={t.done ? 'text-[#9ca3af]' : 'text-accent'}>
                                    {TOOL_ICONS[t.tool]}
                                  </span>
                                  {TOOL_LABELS[t.tool] ?? t.tool}
                                </div>
                                {/* Args hint */}
                                {t.hint && (
                                  <p className="text-[#9ca3af] truncate text-[10px] mt-0.5">{t.hint}</p>
                                )}
                              </div>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  </div>
                </div>
              )}
            </>
          )}
          <div ref={messagesEndRef} />
        </div>

        {/* Error bar */}
        {error && (
          <div className="flex-shrink-0 px-4 md:px-6 py-2 bg-red-50 border-t border-red-200">
            <p className="text-xs text-[#dc2626]">{error}</p>
          </div>
        )}

        {/* Input area */}
        <div className="flex-shrink-0 px-4 md:px-6 py-4 border-t border-beige-300 bg-white/50 backdrop-blur-sm">
          {/* Agent mode toggle */}
          <div className="flex items-center justify-end max-w-4xl mx-auto mb-2">
            <button
              onClick={() => setAgentMode((v) => !v)}
              className={`flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium transition-colors border ${
                agentMode
                  ? 'bg-accent/10 text-accent border-accent/30'
                  : 'bg-transparent text-[#6b7280] border-beige-300 hover:border-accent/30 hover:text-accent/70'
              }`}
              title={agentMode ? 'Mode agent actif — accès au web' : 'Activer le mode agent (accès web)'}
            >
              {/* Globe icon */}
              <svg
                width="12"
                height="12"
                viewBox="0 0 14 14"
                fill="none"
                stroke="currentColor"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <circle cx="7" cy="7" r="5.5" />
                <path d="M7 1.5C7 1.5 5 4 5 7s2 5.5 2 5.5" />
                <path d="M7 1.5C7 1.5 9 4 9 7s-2 5.5-2 5.5" />
                <path d="M1.5 7h11" />
              </svg>
              Mode agent
              {agentMode && (
                <span className="w-1.5 h-1.5 rounded-full bg-accent animate-pulse" />
              )}
            </button>
          </div>

          <div className="flex items-end gap-3 max-w-4xl mx-auto">
            <div className="flex-1 relative">
              <textarea
                ref={textareaRef}
                value={input}
                onChange={handleInputChange}
                onKeyDown={handleKeyDown}
                placeholder={
                  agentMode
                    ? 'Posez une question — l\'agent peut chercher sur internet…'
                    : 'Posez une question sur vos documents…'
                }
                disabled={sending}
                rows={1}
                className="w-full px-4 py-3 bg-white border border-beige-300 rounded-xl text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent resize-none disabled:opacity-50 disabled:cursor-not-allowed"
                style={{ minHeight: '44px', maxHeight: '120px' }}
              />
            </div>
            <button
              onClick={handleSend}
              disabled={!input.trim() || sending}
              className="flex-shrink-0 w-11 h-11 bg-accent hover:bg-accent-hover text-white rounded-xl flex items-center justify-center disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {sending ? (
                <span className="w-5 h-5 border-2 border-white/30 border-t-white rounded-full animate-spin" />
              ) : (
                <svg
                  width="18"
                  height="18"
                  viewBox="0 0 18 18"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M2 9L16 2L9 16L7.5 10.5L2 9Z" />
                </svg>
              )}
            </button>
          </div>
          <p className="text-[10px] text-[#6b7280] text-center mt-2">
            Entrée pour envoyer · Shift+Entrée pour un saut de ligne
          </p>
        </div>
      </div>
    </div>
  );
}
