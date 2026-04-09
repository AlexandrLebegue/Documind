'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useState, useEffect } from 'react';
import UploadModal from './UploadModal';
import { getAlerts } from '@/lib/api';

const navItems = [
  {
    label: 'Tableau de bord',
    href: '/',
    icon: (
      <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 10L10 3L17 10" />
        <path d="M5 10V16C5 16.5 5.5 17 6 17H8.5V12.5C8.5 12 9 11.5 9.5 11.5H10.5C11 11.5 11.5 12 11.5 12.5V17H14C14.5 17 15 16.5 15 16V10" />
      </svg>
    ),
  },
  {
    label: 'Documents',
    href: '/documents',
    icon: (
      <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 5C3 4 3.5 3 5 3H8L10 5H15C16.5 5 17 6 17 7V15C17 16 16.5 17 15 17H5C3.5 17 3 16 3 15V5Z" />
      </svg>
    ),
  },
  {
    label: 'Procédures',
    href: '/procedures',
    icon: (
      <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M6 3H14C15 3 16 4 16 5V15C16 16 15 17 14 17H6C5 17 4 16 4 15V5C4 4 5 3 6 3Z" />
        <path d="M8 7H12" />
        <path d="M8 10H12" />
        <path d="M8 13H11" />
        <path d="M6 7L7 8L6 7Z" fill="currentColor" />
        <circle cx="6.5" cy="7.5" r="0.5" fill="currentColor" />
        <circle cx="6.5" cy="10.5" r="0.5" fill="currentColor" />
        <circle cx="6.5" cy="13.5" r="0.5" fill="currentColor" />
      </svg>
    ),
  },
  {
    label: 'Alertes',
    href: '/alerts',
    icon: (
      <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M10 2.5L17.5 16H2.5L10 2.5Z" />
        <path d="M10 8V11.5" />
        <circle cx="10" cy="14" r="0.5" fill="currentColor" />
      </svg>
    ),
    hasBadge: true,
  },
  {
    label: 'Chat',
    href: '/chat',
    icon: (
      <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M4 4H16C17 4 17 5 17 5V13C17 14 16 14 16 14H11L7 17V14H4C3 14 3 13 3 13V5C3 4 4 4 4 4Z" />
      </svg>
    ),
  },
];

interface SidebarProps {
  isOpen: boolean;
  onClose: () => void;
}

export default function Sidebar({ isOpen, onClose }: SidebarProps) {
  const pathname = usePathname();
  const [uploadOpen, setUploadOpen] = useState(false);
  const [alertCount, setAlertCount] = useState(0);

  useEffect(() => {
    getAlerts({ days_ahead: 30, limit: 1 })
      .then((data) => {
        setAlertCount((data.overdue_count || 0) + (data.expiring_count || 0));
      })
      .catch(() => {});
  }, []);

  const isActive = (href: string) => {
    if (href === '/') return pathname === '/';
    return pathname.startsWith(href);
  };

  return (
    <>
      <aside
        className={`w-60 h-screen bg-beige-200 border-r border-beige-300 flex flex-col overflow-hidden fixed left-0 top-0 z-40 transform transition-transform duration-300 ease-in-out ${
          isOpen ? 'translate-x-0' : '-translate-x-full'
        } md:translate-x-0`}
      >
        {/* Logo + Close button (mobile) */}
        <div className="px-5 py-6 border-b border-beige-300 flex items-center justify-between">
          <Link href="/" className="flex items-center gap-3" onClick={onClose}>
            <div className="w-9 h-9 bg-accent rounded-lg flex items-center justify-center">
              <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="white" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M5 3H12L15 6V17H5V3Z" />
                <path d="M12 3V6H15" />
                <path d="M7 10H13" />
                <path d="M7 13H11" />
              </svg>
            </div>
            <span className="text-lg font-bold text-[#1a1a1a]">DocuMind</span>
          </Link>
          {/* Close button - mobile only */}
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-[#6b7280] hover:text-[#1a1a1a] hover:bg-beige-300/60 transition-colors md:hidden"
            aria-label="Fermer le menu"
          >
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M5 5L15 15" />
              <path d="M15 5L5 15" />
            </svg>
          </button>
        </div>

        {/* Navigation */}
        <nav className="flex-1 overflow-y-auto px-3 py-4 space-y-1">
          {navItems.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              onClick={onClose}
              className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors ${
                isActive(item.href)
                  ? 'bg-accent text-white'
                  : 'text-[#1a1a1a] hover:bg-beige-300/60'
              }`}
            >
              {item.icon}
              {item.label}
              {'hasBadge' in item && item.hasBadge && alertCount > 0 && (
                <span className="ml-auto flex items-center justify-center w-5 h-5 text-[10px] font-bold bg-red-500 text-white rounded-full">
                  {alertCount > 9 ? '9+' : alertCount}
                </span>
              )}
            </Link>
          ))}
        </nav>

        {/* Bottom section: Logs + Settings + Upload */}
        <div className="flex-shrink-0 px-3 pb-5 space-y-2">
          {/* Logs link */}
          <Link
            href="/logs"
            onClick={onClose}
            className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors ${
              isActive('/logs')
                ? 'bg-accent text-white'
                : 'text-[#6b7280] hover:text-[#1a1a1a] hover:bg-beige-300/60'
            }`}
          >
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="3" width="14" height="14" rx="2" />
              <path d="M6 7H14" />
              <path d="M6 10H14" />
              <path d="M6 13H10" />
            </svg>
            Logs
          </Link>

          {/* Settings link */}
          <Link
            href="/settings"
            onClick={onClose}
            className={`flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-colors ${
              isActive('/settings')
                ? 'bg-accent text-white'
                : 'text-[#6b7280] hover:text-[#1a1a1a] hover:bg-beige-300/60'
            }`}
          >
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="10" cy="10" r="3" />
              <path d="M10 1.5V4" />
              <path d="M10 16V18.5" />
              <path d="M1.5 10H4" />
              <path d="M16 10H18.5" />
              <path d="M3.99 3.99L5.76 5.76" />
              <path d="M14.24 14.24L16.01 16.01" />
              <path d="M3.99 16.01L5.76 14.24" />
              <path d="M14.24 5.76L16.01 3.99" />
            </svg>
            Paramètres
          </Link>

          {/* Upload Button */}
          <button
            onClick={() => setUploadOpen(true)}
            className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-accent hover:bg-accent-hover text-white rounded-lg text-sm font-medium transition-colors"
          >
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <circle cx="9" cy="9" r="7" />
              <path d="M9 6V12" />
              <path d="M6 9H12" />
            </svg>
            Ajouter un document
          </button>
        </div>
      </aside>

      <UploadModal
        isOpen={uploadOpen}
        onClose={() => setUploadOpen(false)}
        onUploadComplete={() => {
          setUploadOpen(false);
          onClose();
          // Trigger a page refresh to show new documents
          window.location.reload();
        }}
      />
    </>
  );
}
