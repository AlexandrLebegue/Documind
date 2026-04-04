'use client';

import { useState } from 'react';
import Link from 'next/link';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import type { Components } from 'react-markdown';
import type { ChatMessage as ChatMessageType, ToolCallLog } from '@/lib/api';

interface ChatMessageProps {
  message: ChatMessageType;
}

const TOOL_LABELS: Record<string, string> = {
  recherche_web: 'Recherche web',
  scraper_page: 'Lecture de page',
  verifier_liens: 'Vérification de liens',
  crawler_procedures: 'Crawl de site',
  creer_procedure: 'Création de procédure',
};

function MarkdownContent({ content, isUser }: { content: string; isUser: boolean }) {
  const components: Components = {
    p: ({ children }) => (
      <p className="mb-2 last:mb-0 leading-relaxed">{children}</p>
    ),
    h1: ({ children }) => (
      <h1 className={`text-base font-bold mb-2 mt-3 first:mt-0 ${isUser ? 'text-white' : 'text-[#1a1a1a]'}`}>{children}</h1>
    ),
    h2: ({ children }) => (
      <h2 className={`text-sm font-bold mb-1.5 mt-3 first:mt-0 ${isUser ? 'text-white' : 'text-[#1a1a1a]'}`}>{children}</h2>
    ),
    h3: ({ children }) => (
      <h3 className={`text-sm font-semibold mb-1 mt-2 first:mt-0 ${isUser ? 'text-white' : 'text-[#1a1a1a]'}`}>{children}</h3>
    ),
    ul: ({ children }) => (
      <ul className="list-disc list-outside pl-4 mb-2 space-y-0.5">{children}</ul>
    ),
    ol: ({ children }) => (
      <ol className="list-decimal list-outside pl-4 mb-2 space-y-0.5">{children}</ol>
    ),
    li: ({ children }) => (
      <li className="leading-relaxed">{children}</li>
    ),
    strong: ({ children }) => (
      <strong className="font-semibold">{children}</strong>
    ),
    em: ({ children }) => (
      <em className="italic">{children}</em>
    ),
    code: ({ children, className }) => {
      const isBlock = className?.includes('language-');
      if (isBlock) {
        return (
          <code className={`block text-xs font-mono rounded-lg p-3 mb-2 overflow-x-auto whitespace-pre ${isUser ? 'bg-white/20 text-white' : 'bg-beige-100 text-[#1a1a1a]'}`}>
            {children}
          </code>
        );
      }
      return (
        <code className={`text-xs font-mono rounded px-1.5 py-0.5 ${isUser ? 'bg-white/20 text-white' : 'bg-beige-100 text-[#1a1a1a]'}`}>
          {children}
        </code>
      );
    },
    pre: ({ children }) => (
      <pre className="mb-2 overflow-x-auto">{children}</pre>
    ),
    blockquote: ({ children }) => (
      <blockquote className={`border-l-2 pl-3 mb-2 italic ${isUser ? 'border-white/50 text-white/80' : 'border-accent/40 text-[#6b7280]'}`}>
        {children}
      </blockquote>
    ),
    hr: () => (
      <hr className={`my-2 border-0 border-t ${isUser ? 'border-white/20' : 'border-beige-200'}`} />
    ),
    a: ({ href, children }) => (
      <a
        href={href}
        target="_blank"
        rel="noopener noreferrer"
        className={`underline underline-offset-2 ${isUser ? 'text-white/90 hover:text-white' : 'text-accent hover:text-accent-hover'}`}
      >
        {children}
      </a>
    ),
    table: ({ children }) => (
      <div className="overflow-x-auto mb-2">
        <table className={`text-xs border-collapse w-full ${isUser ? '' : 'border border-beige-300'}`}>
          {children}
        </table>
      </div>
    ),
    th: ({ children }) => (
      <th className={`px-2 py-1 text-left font-semibold border ${isUser ? 'border-white/20 bg-white/10' : 'border-beige-300 bg-beige-100'}`}>
        {children}
      </th>
    ),
    td: ({ children }) => (
      <td className={`px-2 py-1 border ${isUser ? 'border-white/20' : 'border-beige-300'}`}>
        {children}
      </td>
    ),
  };

  return (
    <ReactMarkdown remarkPlugins={[remarkGfm]} components={components}>
      {content}
    </ReactMarkdown>
  );
}

function ToolCallsPanel({ toolCalls }: { toolCalls: ToolCallLog[] }) {
  const [open, setOpen] = useState(false);

  return (
    <div className="mt-2 pt-2 border-t border-beige-200/50">
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-1.5 text-xs text-[#6b7280] hover:text-[#1a1a1a] transition-colors"
      >
        {/* Wrench icon */}
        <svg
          width="11"
          height="11"
          viewBox="0 0 14 14"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M9.5 1.5a3 3 0 0 1 0 4.24L4 11.25 1.5 12.5l1.25-2.5 5.51-5.5A3 3 0 0 1 9.5 1.5Z" />
        </svg>
        <span>
          {toolCalls.length} outil{toolCalls.length > 1 ? 's' : ''} utilisé{toolCalls.length > 1 ? 's' : ''}
        </span>
        {/* Chevron */}
        <svg
          width="10"
          height="10"
          viewBox="0 0 10 10"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.5"
          strokeLinecap="round"
          strokeLinejoin="round"
          className={`transition-transform ${open ? 'rotate-180' : ''}`}
        >
          <path d="M2 3.5L5 6.5L8 3.5" />
        </svg>
      </button>

      {open && (
        <div className="mt-2 space-y-2">
          {toolCalls.map((tc, i) => (
            <div
              key={i}
              className="rounded-lg border border-beige-200 bg-beige-50 px-3 py-2 text-xs"
            >
              <div className="flex items-center gap-1.5 font-medium text-[#1a1a1a] mb-1">
                <span className="inline-flex items-center justify-center w-4 h-4 rounded-full bg-accent/10 text-accent text-[9px] font-bold flex-shrink-0">
                  {i + 1}
                </span>
                {TOOL_LABELS[tc.tool] ?? tc.tool}
              </div>
              {/* Args summary */}
              <p className="text-[#6b7280] truncate">
                {Object.entries(tc.args)
                  .map(([k, v]) => `${k}: ${JSON.stringify(v)}`)
                  .join(' · ')}
              </p>
              {/* Result preview */}
              {tc.result_preview && (
                <p className="mt-1 text-[#6b7280] line-clamp-2 break-words">
                  {tc.result_preview}
                </p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

export default function ChatMessage({ message }: ChatMessageProps) {
  const isUser = message.role === 'user';

  const formattedTime = new Date(message.created_at).toLocaleTimeString('fr-FR', {
    hour: '2-digit',
    minute: '2-digit',
  });

  return (
    <div className={`flex ${isUser ? 'justify-end' : 'justify-start'} mb-4`}>
      <div className={`max-w-[75%] ${isUser ? 'order-1' : 'order-1'}`}>
        {/* Avatar indicator */}
        <div className={`flex items-end gap-2 ${isUser ? 'flex-row-reverse' : 'flex-row'}`}>
          {/* Avatar */}
          <div
            className={`flex-shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold ${
              isUser
                ? 'bg-accent text-white'
                : 'bg-beige-200 text-[#6b7280]'
            }`}
          >
            {isUser ? 'V' : 'D'}
          </div>

          {/* Bubble */}
          <div
            className={`px-4 py-2.5 rounded-2xl ${
              isUser
                ? 'bg-accent text-white rounded-br-md'
                : 'bg-white border border-beige-300/50 text-[#1a1a1a] rounded-bl-md shadow-sm'
            }`}
          >
            {/* Message text — markdown rendered */}
            <div className="text-sm">
              <MarkdownContent content={message.message} isUser={isUser} />
            </div>

            {/* Tool calls (agent mode) */}
            {!isUser && message.tool_calls && message.tool_calls.length > 0 && (
              <ToolCallsPanel toolCalls={message.tool_calls} />
            )}

            {/* Source documents (RAG mode) */}
            {!isUser && message.context_doc_ids && message.context_doc_ids.length > 0 && (
              <div className="mt-2 pt-2 border-t border-beige-200/50">
                <p className="text-xs text-[#6b7280] mb-1.5">Sources :</p>
                <div className="flex flex-wrap gap-1.5">
                  {message.context_doc_ids.map((docId) => (
                    <Link
                      key={docId}
                      href={`/documents/view?id=${docId}`}
                      className="inline-flex items-center gap-1 px-2 py-0.5 bg-beige-100 hover:bg-beige-200 text-[#1a1a1a] text-xs rounded-full transition-colors"
                      onClick={(e) => e.stopPropagation()}
                    >
                      <svg width="10" height="10" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                        <path d="M3 2H8L11 5V12H3V2Z" />
                        <path d="M8 2V5H11" />
                      </svg>
                      Doc {docId.slice(0, 8)}...
                    </Link>
                  ))}
                </div>
              </div>
            )}

            {/* Timestamp */}
            <p
              className={`text-[10px] mt-1 ${
                isUser ? 'text-white/60' : 'text-[#6b7280]/60'
              }`}
            >
              {formattedTime}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
