'use client';

import { useState, useEffect } from 'react';
import { usePathname } from 'next/navigation';
import Link from 'next/link';
import Sidebar from './Sidebar';
import QueueIndicator from './QueueIndicator';

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
      <header className="fixed top-0 left-0 right-0 z-30 flex items-center h-14 px-4 bg-beige-200 border-b border-beige-300 md:hidden">
        <button
          onClick={() => setSidebarOpen(true)}
          className="p-2 -ml-2 rounded-lg text-[#1a1a1a] hover:bg-beige-300/60 transition-colors"
          aria-label="Ouvrir le menu"
        >
          <svg width="22" height="22" viewBox="0 0 22 22" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <path d="M4 6H18" />
            <path d="M4 11H18" />
            <path d="M4 16H18" />
          </svg>
        </button>
        <Link href="/" className="flex items-center gap-2.5 ml-3">
          <div className="w-8 h-8 bg-accent rounded-lg flex items-center justify-center">
            <svg width="16" height="16" viewBox="0 0 20 20" fill="none" stroke="white" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M5 3H12L15 6V17H5V3Z" />
              <path d="M12 3V6H15" />
              <path d="M7 10H13" />
              <path d="M7 13H11" />
            </svg>
          </div>
          <span className="text-base font-bold text-[#1a1a1a]">DocuMind</span>
        </Link>
      </header>

      {/* Backdrop overlay (mobile only) */}
      {sidebarOpen && (
        <div
          className="fixed inset-0 z-35 bg-black/40 md:hidden"
          style={{ zIndex: 35 }}
          onClick={() => setSidebarOpen(false)}
          aria-hidden="true"
        />
      )}

      <div className="flex min-h-screen">
        <Sidebar isOpen={sidebarOpen} onClose={() => setSidebarOpen(false)} />
        <main className="flex-1 ml-0 md:ml-60 pt-14 md:pt-0 min-h-screen overflow-auto">
          {children}
        </main>
      </div>
      <QueueIndicator />
    </>
  );
}
