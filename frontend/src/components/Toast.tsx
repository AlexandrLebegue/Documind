'use client';

import { useEffect, useState } from 'react';

type ToastKind = 'success' | 'error' | 'info';

interface ToastItem {
  id: number;
  message: string;
  kind: ToastKind;
}

const TOAST_EVENT = 'documind-toast';

export function toast(message: string, kind: ToastKind = 'info') {
  if (typeof window === 'undefined') return;
  window.dispatchEvent(new CustomEvent(TOAST_EVENT, { detail: { message, kind } }));
}

const KIND_CONFIG: Record<ToastKind, { bg: string; border: string; text: string; icon: React.ReactNode }> = {
  success: {
    bg: 'bg-emerald-50',
    border: 'border-emerald-200',
    text: 'text-emerald-800',
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="8" cy="8" r="6.5" />
        <path d="M5 8L7 10L11 6" />
      </svg>
    ),
  },
  error: {
    bg: 'bg-red-50',
    border: 'border-red-200',
    text: 'text-red-800',
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="8" cy="8" r="6.5" />
        <path d="M8 5V8.5" />
        <circle cx="8" cy="11" r="0.5" fill="currentColor" />
      </svg>
    ),
  },
  info: {
    bg: 'bg-blue-50',
    border: 'border-blue-200',
    text: 'text-blue-800',
    icon: (
      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="8" cy="8" r="6.5" />
        <path d="M8 7.5V11" />
        <circle cx="8" cy="5" r="0.5" fill="currentColor" />
      </svg>
    ),
  },
};

export default function ToastHost() {
  const [items, setItems] = useState<ToastItem[]>([]);

  useEffect(() => {
    const onToast = (event: Event) => {
      const detail = (event as CustomEvent<{ message: string; kind?: ToastKind }>).detail;
      if (!detail?.message) return;
      const item = { id: Date.now() + Math.random(), message: detail.message, kind: detail.kind || 'info' };
      setItems((prev) => [...prev.slice(-3), item]);
      window.setTimeout(() => {
        setItems((prev) => prev.filter((t) => t.id !== item.id));
      }, 3800);
    };
    window.addEventListener(TOAST_EVENT, onToast);
    return () => window.removeEventListener(TOAST_EVENT, onToast);
  }, []);

  if (items.length === 0) return null;

  return (
    <div className="fixed inset-x-3 bottom-3 z-[70] flex flex-col items-center gap-2 sm:inset-x-auto sm:right-5 sm:bottom-5 sm:items-end pointer-events-none safe-bottom">
      {items.map((item) => {
        const config = KIND_CONFIG[item.kind];
        return (
          <div
            key={item.id}
            role="status"
            className={`animate-toast-in pointer-events-auto flex w-full max-w-sm items-start gap-2.5 rounded-xl border px-4 py-3 shadow-lg ${config.bg} ${config.border} ${config.text}`}
          >
            <span className="mt-0.5 flex-shrink-0">{config.icon}</span>
            <p className="text-sm font-medium leading-snug">{item.message}</p>
            <button
              onClick={() => setItems((prev) => prev.filter((t) => t.id !== item.id))}
              className="ml-auto flex-shrink-0 rounded p-1 opacity-60 hover:opacity-100"
              aria-label="Fermer la notification"
            >
              <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <path d="M2 2L10 10" />
                <path d="M10 2L2 10" />
              </svg>
            </button>
          </div>
        );
      })}
    </div>
  );
}
