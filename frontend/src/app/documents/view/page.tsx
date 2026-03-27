'use client';

import { useState, useEffect, Suspense } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { getDocument, updateDocument, deleteDocument, reprocessDocument, getDocumentFileUrl } from '@/lib/api';
import type { Document } from '@/lib/api';
import StatusBadge from '@/components/StatusBadge';
import MetadataEditor from '@/components/MetadataEditor';
import { ExpiryBadge, EcheanceBadge } from '@/components/AlertBadge';

function DocumentDetailContent() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const id = searchParams.get('id') || '';

  const [doc, setDoc] = useState<Document | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showFullText, setShowFullText] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [reprocessing, setReprocessing] = useState(false);
  const [deleting, setDeleting] = useState(false);

  useEffect(() => {
    if (!id) {
      setError('Aucun identifiant de document fourni');
      setLoading(false);
      return;
    }
    async function fetchDoc() {
      try {
        const data = await getDocument(id);
        setDoc(data);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erreur de chargement');
      } finally {
        setLoading(false);
      }
    }
    fetchDoc();
  }, [id]);

  const handleSave = async (updates: Partial<Document>) => {
    try {
      const updated = await updateDocument(id, updates);
      setDoc(updated);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Erreur lors de la sauvegarde');
    }
  };

  const handleReprocess = async () => {
    setReprocessing(true);
    try {
      await reprocessDocument(id);
      const refreshed = await getDocument(id);
      setDoc(refreshed);
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Erreur lors du retraitement');
    } finally {
      setReprocessing(false);
    }
  };

  const handleDelete = async () => {
    setDeleting(true);
    try {
      await deleteDocument(id);
      router.push('/documents');
    } catch (err) {
      alert(err instanceof Error ? err.message : 'Erreur lors de la suppression');
      setDeleting(false);
    }
  };

  if (loading) {
    return (
      <div className="p-6">
        <div className="skeleton h-6 w-32 mb-6" />
        <div className="grid grid-cols-5 gap-6">
          <div className="col-span-3 skeleton h-96 rounded-xl" />
          <div className="col-span-2 space-y-4">
            <div className="skeleton h-8 w-full" />
            {[...Array(7)].map((_, i) => (
              <div key={i} className="skeleton h-10 w-full" />
            ))}
          </div>
        </div>
      </div>
    );
  }

  if (error || !doc) {
    return (
      <div className="p-6">
        <div className="bg-red-50 border border-red-200 rounded-xl p-6 text-center">
          <p className="text-[#dc2626] font-medium">Document introuvable</p>
          <p className="text-sm text-[#6b7280] mt-1">{error || 'Le document demandé n\'existe pas'}</p>
          <button
            onClick={() => router.push('/documents')}
            className="mt-3 px-4 py-2 text-sm bg-accent hover:bg-accent-hover text-white rounded-lg"
          >
            Retour aux documents
          </button>
        </div>
      </div>
    );
  }

  const textContent = doc.text_content || '';
  const truncatedText = textContent.slice(0, 500);
  const hasMoreText = textContent.length > 500;

  // Determine file type for preview rendering
  const fileExt = doc.filename.split('.').pop()?.toLowerCase() || '';
  const isImage = ['jpg', 'jpeg', 'png', 'webp'].includes(fileExt);
  const isPdf = fileExt === 'pdf';
  const isTiff = fileExt === 'tiff' || fileExt === 'tif';
  const fileUrl = getDocumentFileUrl(doc.id);

  return (
    <div className="p-6">
      {/* Back button */}
      <button
        onClick={() => router.push('/documents')}
        className="flex items-center gap-1.5 text-sm text-[#6b7280] hover:text-[#1a1a1a] mb-4 transition-colors"
      >
        <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <path d="M10 3L5 8L10 13" />
        </svg>
        Retour aux documents
        </button>
  
        {/* Expiry / Echeance alert banner */}
        {doc.date_expiration && (() => {
          const today = new Date();
          today.setHours(0, 0, 0, 0);
          const expDate = new Date(doc.date_expiration);
          expDate.setHours(0, 0, 0, 0);
          const daysRem = Math.ceil((expDate.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));
          if (daysRem <= 30) {
            const isOverdue = daysRem < 0;
            return (
              <div className={`mb-4 rounded-xl border p-4 flex items-center justify-between ${
                isOverdue || daysRem <= 7
                  ? 'bg-red-50 border-red-200'
                  : 'bg-amber-50 border-amber-200'
              }`}>
                <div className="flex items-center gap-3">
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={isOverdue || daysRem <= 7 ? '#dc2626' : '#d97706'} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M12 3L21 19H3L12 3Z" />
                    <path d="M12 10V14" />
                    <circle cx="12" cy="17" r="0.5" fill={isOverdue || daysRem <= 7 ? '#dc2626' : '#d97706'} />
                  </svg>
                  <div>
                    <p className={`text-sm font-medium ${isOverdue || daysRem <= 7 ? 'text-red-800' : 'text-amber-800'}`}>
                      {isOverdue
                        ? `Ce document a expiré il y a ${Math.abs(daysRem)} jours`
                        : `Ce document expire dans ${daysRem} jours`}
                    </p>
                    <p className={`text-xs ${isOverdue || daysRem <= 7 ? 'text-red-600' : 'text-amber-600'}`}>
                      Date d&apos;expiration : {expDate.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}
                    </p>
                  </div>
                </div>
                <Link
                  href="/alerts"
                  className={`text-xs font-medium px-3 py-1.5 rounded-lg ${
                    isOverdue || daysRem <= 7
                      ? 'bg-red-100 text-red-700 hover:bg-red-200'
                      : 'bg-amber-100 text-amber-700 hover:bg-amber-200'
                  } transition-colors`}
                >
                  Voir les alertes
                </Link>
              </div>
            );
          }
          return null;
        })()}
  
        {doc.date_echeance && (() => {
          const today = new Date();
          today.setHours(0, 0, 0, 0);
          const echDate = new Date(doc.date_echeance);
          echDate.setHours(0, 0, 0, 0);
          const daysRem = Math.ceil((echDate.getTime() - today.getTime()) / (1000 * 60 * 60 * 24));
          if (daysRem <= 30) {
            const isOverdue = daysRem < 0;
            return (
              <div className={`mb-4 rounded-xl border p-4 flex items-center gap-3 ${
                isOverdue || daysRem <= 7
                  ? 'bg-red-50 border-red-200'
                  : 'bg-amber-50 border-amber-200'
              }`}>
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={isOverdue || daysRem <= 7 ? '#dc2626' : '#d97706'} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <circle cx="12" cy="12" r="9" />
                  <path d="M12 7V12L15 15" />
                </svg>
                <div>
                  <p className={`text-sm font-medium ${isOverdue || daysRem <= 7 ? 'text-red-800' : 'text-amber-800'}`}>
                    {isOverdue
                      ? `Échéance de paiement dépassée de ${Math.abs(daysRem)} jours`
                      : `Échéance de paiement dans ${daysRem} jours`}
                  </p>
                  <p className={`text-xs ${isOverdue || daysRem <= 7 ? 'text-red-600' : 'text-amber-600'}`}>
                    Date d&apos;échéance : {echDate.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}
                  </p>
                </div>
              </div>
            );
          }
          return null;
        })()}
  
        {/* Two-panel layout */}
      <div className="grid grid-cols-1 lg:grid-cols-5 gap-6">
        {/* Left panel: File preview */}
        <div className="lg:col-span-3">
          <div className="bg-beige-200 rounded-xl border border-beige-300 overflow-hidden min-h-[400px] flex flex-col">
            {isImage && (
              <div className="flex items-center justify-center p-4 flex-1">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img
                  src={fileUrl}
                  alt={doc.filename}
                  className="max-w-full max-h-[70vh] object-contain rounded-lg shadow-sm"
                />
              </div>
            )}

            {isPdf && (
              <object
                data={`${fileUrl}#toolbar=1&view=FitH`}
                type="application/pdf"
                className="w-full flex-1 min-h-[600px]"
              >
                <div className="flex flex-col items-center justify-center p-8 flex-1 text-center">
                  <p className="text-sm text-[#6b7280] mb-4">
                    Impossible d&apos;afficher le PDF dans le navigateur
                  </p>
                  <a
                    href={fileUrl}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-flex items-center gap-2 px-4 py-2 bg-accent hover:bg-accent-hover text-white text-sm font-medium rounded-lg transition-colors"
                  >
                    <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M8 3V11" />
                      <path d="M4 8L8 12L12 8" />
                      <path d="M3 14H13" />
                    </svg>
                    Ouvrir le PDF
                  </a>
                </div>
              </object>
            )}

            {isTiff && (
              <div className="flex flex-col items-center justify-center p-8 flex-1 text-center">
                <svg width="64" height="64" viewBox="0 0 64 64" fill="none" stroke="#6b7280" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="mx-auto mb-4">
                  <path d="M16 8H38L50 20V56H16V8Z" />
                  <path d="M38 8V20H50" />
                  <path d="M24 32H42" />
                  <path d="M24 40H38" />
                  <path d="M24 48H34" />
                </svg>
                <p className="text-lg font-semibold text-[#1a1a1a] mb-1">{doc.filename}</p>
                <p className="text-sm text-[#6b7280] mb-4">
                  Le format TIFF ne peut pas être affiché dans le navigateur
                </p>
                <a
                  href={fileUrl}
                  download={doc.filename}
                  className="inline-flex items-center gap-2 px-4 py-2 bg-accent hover:bg-accent-hover text-white text-sm font-medium rounded-lg transition-colors"
                >
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M8 3V11" />
                    <path d="M4 8L8 12L12 8" />
                    <path d="M3 14H13" />
                  </svg>
                  Télécharger le fichier
                </a>
              </div>
            )}

            {!isImage && !isPdf && !isTiff && (
              <div className="flex flex-col items-center justify-center p-8 flex-1 text-center">
                <svg width="64" height="64" viewBox="0 0 64 64" fill="none" stroke="#6b7280" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="mx-auto mb-4">
                  <path d="M16 8H38L50 20V56H16V8Z" />
                  <path d="M38 8V20H50" />
                  <path d="M24 32H42" />
                  <path d="M24 40H38" />
                  <path d="M24 48H34" />
                </svg>
                <p className="text-lg font-semibold text-[#1a1a1a] mb-1">{doc.filename}</p>
                <p className="text-sm text-[#6b7280]">
                  Prévisualisation non disponible pour ce format
                </p>
              </div>
            )}
          </div>

          {/* OCR Text section */}
          {textContent && (
            <div className="mt-6 bg-white rounded-xl border border-beige-300/50 p-5">
              <h3 className="text-sm font-semibold text-[#1a1a1a] mb-3 flex items-center gap-2">
                <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M2 4H14" />
                  <path d="M2 8H10" />
                  <path d="M2 12H12" />
                </svg>
                Texte extrait (OCR)
              </h3>
              <div className="text-sm text-[#1a1a1a] whitespace-pre-wrap leading-relaxed bg-beige-50 rounded-lg p-4 border border-beige-300/30">
                {showFullText ? textContent : truncatedText}
                {hasMoreText && !showFullText && '...'}
              </div>
              {hasMoreText && (
                <button
                  onClick={() => setShowFullText(!showFullText)}
                  className="mt-2 text-sm text-accent hover:text-accent-hover font-medium"
                >
                  {showFullText ? 'Voir moins' : 'Voir plus'}
                </button>
              )}
            </div>
          )}
        </div>

        {/* Right panel: Metadata */}
        <div className="lg:col-span-2 space-y-6">
          {/* Document title and status */}
          <div className="bg-white rounded-xl border border-beige-300/50 p-5">
            <div className="flex items-start justify-between mb-2">
              <h2 className="text-lg font-bold text-[#1a1a1a] break-all pr-4">{doc.title || doc.filename}</h2>
              <StatusBadge status={doc.status} />
            </div>
            {doc.title && (
              <p className="text-xs text-[#6b7280] mb-1 truncate" title={doc.filename}>
                📄 {doc.filename}
              </p>
            )}
            <p className="text-xs text-[#6b7280]">
              Ajouté le {new Date(doc.created_at).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
            </p>
          </div>

          {/* Metadata editor */}
          <div className="bg-white rounded-xl border border-beige-300/50 p-5">
            <h3 className="text-sm font-semibold text-[#1a1a1a] mb-4">Métadonnées</h3>
            <MetadataEditor document={doc} onSave={handleSave} />
          </div>

          {/* Action buttons */}
          <div className="space-y-2">
            <button
              onClick={handleReprocess}
              disabled={reprocessing}
              className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-white border border-beige-300 rounded-lg text-sm font-medium text-[#1a1a1a] hover:bg-beige-50 disabled:opacity-50 transition-colors"
            >
              {reprocessing ? (
                <>
                  <span className="w-4 h-4 border-2 border-beige-300 border-t-accent rounded-full animate-spin" />
                  Re-analyse en cours...
                </>
              ) : (
                <>
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M2 8C2 4.686 4.686 2 8 2C10.21 2 12.118 3.272 13 5.1" />
                    <path d="M14 8C14 11.314 11.314 14 8 14C5.79 14 3.882 12.728 3 10.9" />
                    <path d="M13 2V5.1H10" />
                    <path d="M3 14V10.9H6" />
                  </svg>
                  Re-analyser le document
                </>
              )}
            </button>

            {!confirmDelete ? (
              <button
                onClick={() => setConfirmDelete(true)}
                className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-white border border-red-200 rounded-lg text-sm font-medium text-[#dc2626] hover:bg-red-50 transition-colors"
              >
                <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M3 5H13" />
                  <path d="M5 5V3C5 2.5 5.5 2 6 2H10C10.5 2 11 2.5 11 3V5" />
                  <path d="M4 5L5 14H11L12 5" />
                </svg>
                Supprimer le document
              </button>
            ) : (
              <div className="bg-red-50 border border-red-200 rounded-lg p-4">
                <p className="text-sm text-[#dc2626] font-medium mb-3">
                  Êtes-vous sûr de vouloir supprimer ce document ?
                </p>
                <div className="flex gap-2">
                  <button
                    onClick={() => setConfirmDelete(false)}
                    className="flex-1 px-3 py-2 text-sm bg-white border border-beige-300 rounded-lg hover:bg-beige-50"
                  >
                    Annuler
                  </button>
                  <button
                    onClick={handleDelete}
                    disabled={deleting}
                    className="flex-1 px-3 py-2 text-sm bg-[#dc2626] text-white rounded-lg hover:bg-red-700 disabled:opacity-50"
                  >
                    {deleting ? 'Suppression...' : 'Confirmer'}
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

export default function DocumentViewPage() {
  return (
    <Suspense fallback={
      <div className="p-6">
        <div className="skeleton h-6 w-32 mb-6" />
        <div className="grid grid-cols-5 gap-6">
          <div className="col-span-3 skeleton h-96 rounded-xl" />
          <div className="col-span-2 space-y-4">
            <div className="skeleton h-8 w-full" />
            {[...Array(7)].map((_, i) => (
              <div key={i} className="skeleton h-10 w-full" />
            ))}
          </div>
        </div>
      </div>
    }>
      <DocumentDetailContent />
    </Suspense>
  );
}
