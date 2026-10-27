'use client';

import { useState, useEffect } from 'react';
import { usePathname } from 'next/navigation';
import Link from 'next/link';
import Sidebar from './Sidebar';
import QueueIndicator from './QueueIndicator';
import ToastHost from './Toast';

export default function LayoutShell({ children }: { children: React.ReactNode }) {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const pathname = usePathname();

  // Auto-close sidebar on route change (mobile navigation)
  useEffect(() => {
    setSidebarOpen(false);
  }, [pathname]);

  // Prevent body scroll when sidebar overlay is open on mobile
  useEffect(() => {
    if (sidebarOpen) {
      document.body.style.overflow = 'hidden';
    } else {
      document.body.style.overflow = '';
    }
    return () => {
      document.body.style.overflow = '';
    };
  }, [sidebarOpen]);

  return (
    <>
      {/* Mobile header bar */}
      <header className="safe-top fixed top-0 left-0 right-0 z-30 border-b border-beige-300 bg-beige-200/95 backdrop-blur-sm md:hidden">
        <div className="flex h-14 items-center px-3">
          <button
            onClick={() => setSidebarOpen(true)}
            className="flex h-11 w-11 items-center justify-center rounded-lg text-[#1a1a1a] hover:bg-beige-300/60 active:scale-95 transition"
            aria-label="Ouvrir le menu"
          >
            <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M4 6H18" />
              <path d="M4 11H18" />
              <path d="M4 16H18" />
            </svg>
          </button>
          <Link href="/" className="ml-1 flex min-w-0 items-center gap-2.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/icon-192.png" alt="" className="h-9 w-9 rounded-xl object-cover shadow-sm" />
            <span className="truncate text-base font-bold text-[#1a1a1a]">DocuMind</span>
          </Link>
        </div>
      </header>

      {/* Backdrop overlay (mobile only) */}
      {sidebarOpen && (
        <div
          className="animate-fade-in fixed inset-0 z-[35] bg-black/40 md:hidden"
          onClick={() => setSidebarOpen(false)}
          aria-hidden="true"
        />
      )}

      <div className="flex min-h-screen w-full overflow-x-hidden">
        <Sidebar isOpen={sidebarOpen} onClose={() => setSidebarOpen(false)} />
        <main className="flex-1 min-w-0 ml-0 md:ml-60 pt-[calc(3.5rem+env(safe-area-inset-top))] md:pt-0 min-h-screen overflow-x-hidden">
          <div key={pathname} className="page-enter min-w-0">
            {children}
          </div>
        </main>
      </div>
      <QueueIndicator />
      <ToastHost />
    </>
  );
}
