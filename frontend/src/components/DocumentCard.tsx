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

function OcrProgress({ document }: { document: Document }) {
  if (document.status !== 'processing' || !document.pages_total) return null;
  const done = Math.min(document.pages_done || 0, document.pages_total || 0);
  const percent = Math.round((done / document.pages_total) * 100);
  return (
    <div className="mt-2">
      <div className="mb-1 flex items-center justify-between text-[10px] text-[#6b7280]">
        <span>OCR page {done}/{document.pages_total}</span>
        <span>{percent}%</span>
      </div>
      <div className="h-1.5 w-full overflow-hidden rounded-full bg-beige-200">
        <div
          className="h-full rounded-full bg-accent transition-[width] duration-300"
          style={{ width: `${percent}%` }}
        />
      </div>
    </div>
  );
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
      <Link href={`/documents/view?id=${document.id}`} className="block min-w-0">
        <div className="group flex min-w-0 items-start gap-3 rounded-xl border border-beige-300/50 bg-white p-4 transition-all hover:border-beige-300 hover:shadow-md active:scale-[0.995] sm:items-center">
          {/* File icon */}
          <div className="hidden h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg bg-beige-100 text-[#6b7280] transition-colors group-hover:bg-accent/10 group-hover:text-accent sm:flex">
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M5 3H12L15 6V17H5V3Z" />
              <path d="M12 3V6H15" />
            </svg>
          </div>

          {/* Info */}
          <div className="min-w-0 flex-1">
            <p className="line-clamp-2 break-words text-sm font-medium leading-snug text-[#1a1a1a]">
              {displayTitle}
            </p>
            {(document.emetteur || formattedDate) && (
              <p className="mt-0.5 truncate text-xs text-[#6b7280]">
                {document.emetteur && <span>{document.emetteur}</span>}
                {document.emetteur && formattedDate && <span> · </span>}
                {formattedDate && <span>{formattedDate}</span>}
              </p>
            )}

            <div className="mt-2 flex flex-wrap items-center gap-1.5">
              <TypeBadge type={document.doc_type} />
              {document.date_expiration && (
                <ExpiryBadge dateExpiration={document.date_expiration} docType={document.doc_type} />
              )}
              {document.date_echeance && (
                <EcheanceBadge dateEcheance={document.date_echeance} />
              )}
              {document.status !== 'ready' && <StatusBadge status={document.status} />}
              {formattedMontant && (
                <span className="ml-auto whitespace-nowrap text-sm font-semibold text-[#1a1a1a]">
                  {formattedMontant}
                </span>
              )}
            </div>

            <OcrProgress document={document} />
          </div>
        </div>
      </Link>
    );
  }

  // Grid view
  return (
    <Link href={`/documents/view?id=${document.id}`} className="block min-w-0">
      <div className="group flex h-full min-h-[150px] min-w-0 flex-col rounded-xl border border-beige-300/50 bg-white p-4 transition-all hover:-translate-y-0.5 hover:border-beige-300 hover:shadow-lg active:scale-[0.99]">
        {/* Badges first: they wrap instead of squeezing the title */}
        <div className="mb-2 flex flex-wrap items-center gap-1.5">
          <TypeBadge type={document.doc_type} />
          {document.date_expiration && (
            <ExpiryBadge dateExpiration={document.date_expiration} docType={document.doc_type} />
          )}
          {document.date_echeance && (
            <EcheanceBadge dateEcheance={document.date_echeance} />
          )}
          {document.status !== 'ready' && <StatusBadge status={document.status} />}
        </div>

        {/* Title on its own line */}
        <h3 className="line-clamp-2 break-words text-sm font-semibold leading-snug text-[#1a1a1a]">
          {displayTitle}
        </h3>

        {/* Emetteur + date */}
        {(document.emetteur || formattedDate) && (
          <p className="mt-1 truncate text-xs text-[#6b7280]">
            {document.emetteur && <span>{document.emetteur}</span>}
            {document.emetteur && formattedDate && <span> · </span>}
            {formattedDate && <span>{formattedDate}</span>}
          </p>
        )}

        {document.resume && (
          <p className="mt-2 line-clamp-2 flex-1 text-xs leading-relaxed text-[#6b7280]">
            {document.resume}
          </p>
        )}
        {!document.resume && <div className="flex-1" />}

        <OcrProgress document={document} />

        {formattedMontant && (
          <div className="mt-3 border-t border-beige-200 pt-2">
            <span className="text-sm font-semibold text-[#1a1a1a]">{formattedMontant}</span>
          </div>
        )}
      </div>
    </Link>
  );
}
