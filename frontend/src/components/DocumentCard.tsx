'use client';

import Link from 'next/link';
import type { Document } from '@/lib/api';
import TypeBadge from './TypeBadge';
import StatusBadge from './StatusBadge';
import { ExpiryBadge, EcheanceBadge } from './AlertBadge';

interface DocumentCardProps {
  document: Document;
  view?: 'grid' | 'list';
}

export default function DocumentCard({ document, view = 'grid' }: DocumentCardProps) {
  const displayTitle = document.title || document.filename;

  const formattedDate = document.doc_date
    ? new Date(document.doc_date).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' })
    : null;

  const formattedMontant = document.montant != null
    ? new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(document.montant)
    : null;

  if (view === 'list') {
    return (
      <Link href={`/documents/view?id=${document.id}`}>
        <div className="flex items-center gap-4 p-4 bg-white rounded-lg border border-beige-300/50 hover:shadow-md hover:border-beige-300 transition-all cursor-pointer group">
          {/* File icon */}
          <div className="flex-shrink-0 w-10 h-10 bg-beige-100 rounded-lg flex items-center justify-center text-[#6b7280] group-hover:bg-accent/10 group-hover:text-accent">
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M5 3H12L15 6V17H5V3Z" />
              <path d="M12 3V6H15" />
            </svg>
          </div>

          {/* Info */}
          <div className="flex-1 min-w-0">
            <p className="text-sm font-medium text-[#1a1a1a] truncate">{displayTitle}</p>
            <p className="text-xs text-[#6b7280] truncate">
              {document.emetteur && <span>{document.emetteur}</span>}
              {document.emetteur && formattedDate && <span> · </span>}
              {formattedDate && <span>{formattedDate}</span>}
            </p>
          </div>

          {/* Type */}
          <div className="flex-shrink-0">
            <TypeBadge type={document.doc_type} />
          </div>

          {/* Expiry / Echeance badges */}
          {document.date_expiration && (
            <div className="flex-shrink-0">
              <ExpiryBadge dateExpiration={document.date_expiration} />
            </div>
          )}
          {document.date_echeance && (
            <div className="flex-shrink-0">
              <EcheanceBadge dateEcheance={document.date_echeance} />
            </div>
          )}

          {/* Montant */}
          {formattedMontant && (
            <div className="flex-shrink-0 text-sm font-semibold text-[#1a1a1a]">
              {formattedMontant}
            </div>
          )}

          {/* Status */}
          {document.status !== 'ready' && (
            <div className="flex-shrink-0">
              <StatusBadge status={document.status} />
            </div>
          )}
        </div>
      </Link>
    );
  }

  // Grid view
  return (
    <Link href={`/documents/view?id=${document.id}`}>
      <div className="bg-white rounded-xl border border-beige-300/50 p-4 hover:shadow-lg hover:border-beige-300 hover:-translate-y-0.5 transition-all cursor-pointer h-full flex flex-col">
        {/* Header row: type badge + status + expiry */}
        <div className="flex items-center justify-between mb-3 gap-1 flex-wrap">
          <TypeBadge type={document.doc_type} />
          <div className="flex items-center gap-1">
            {document.date_expiration && <ExpiryBadge dateExpiration={document.date_expiration} />}
            {document.date_echeance && <EcheanceBadge dateEcheance={document.date_echeance} />}
            {document.status !== 'ready' && <StatusBadge status={document.status} />}
          </div>
        </div>

        {/* Title */}
        <h3 className="text-sm font-semibold text-[#1a1a1a] truncate mb-1">{displayTitle}</h3>

        {/* Emetteur + date */}
        <p className="text-xs text-[#6b7280] mb-2">
          {document.emetteur && <span>{document.emetteur}</span>}
          {document.emetteur && formattedDate && <span> · </span>}
          {formattedDate && <span>{formattedDate}</span>}
        </p>

        {/* Resume */}
        {document.resume && (
          <p className="text-xs text-[#6b7280] line-clamp-2 mb-3 flex-1">
            {document.resume}
          </p>
        )}
        {!document.resume && <div className="flex-1" />}

        {/* Footer: montant */}
        {formattedMontant && (
          <div className="pt-2 border-t border-beige-200">
            <span className="text-sm font-semibold text-[#1a1a1a]">{formattedMontant}</span>
          </div>
        )}
      </div>
    </Link>
  );
}
