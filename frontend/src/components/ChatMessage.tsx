'use client';

import Link from 'next/link';
import type { ChatMessage as ChatMessageType } from '@/lib/api';

interface ChatMessageProps {
  message: ChatMessageType;
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
            {/* Message text */}
            <p className="text-sm whitespace-pre-wrap leading-relaxed">{message.message}</p>

            {/* Source documents */}
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
