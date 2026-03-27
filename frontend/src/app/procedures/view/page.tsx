'use client';

import { useState, useEffect, Suspense } from 'react';
import Link from 'next/link';
import { useSearchParams, useRouter } from 'next/navigation';
import { getProcedure, executeProcedure, deleteProcedure, getDocumentFileUrl } from '@/lib/api';
import type { Procedure, ProcedureExecution, MatchedDocument } from '@/lib/api';
import ProcedureTypeBadge from '@/components/ProcedureTypeBadge';
import TypeBadge from '@/components/TypeBadge';

function ProcedureDetailContent() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const procId = searchParams.get('id') || '';

  const [procedure, setProcedure] = useState<Procedure | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Execution state
  const [showExecute, setShowExecute] = useState(false);
  const [personName, setPersonName] = useState('');
  const [executing, setExecuting] = useState(false);
  const [execution, setExecution] = useState<ProcedureExecution | null>(null);
  const [execError, setExecError] = useState<string | null>(null);

  useEffect(() => {
    if (!procId) {
      setError('Aucun identifiant de procédure fourni');
      setLoading(false);
      return;
    }
    async function loadProcedure() {
      try {
        const proc = await getProcedure(procId);
        setProcedure(proc);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erreur de chargement');
      } finally {
        setLoading(false);
      }
    }
    loadProcedure();
  }, [procId]);

  const handleDelete = async () => {
    if (!confirm('Êtes-vous sûr de vouloir supprimer cette procédure ?')) return;
    try {
      await deleteProcedure(procId);
      router.push('/procedures');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur lors de la suppression');
    }
  };

  const handleExecute = async () => {
    if (!personName.trim()) return;
    setExecuting(true);
    setExecError(null);
    setExecution(null);

    try {
      const result = await executeProcedure(procId, personName.trim());
      setExecution(result);
    } catch (err) {
      setExecError(err instanceof Error ? err.message : 'Erreur lors de l\'exécution');
    } finally {
      setExecuting(false);
    }
  };

  if (loading) {
    return (
      <div className="p-6 space-y-6">
        <div className="skeleton h-8 w-64 rounded-lg" />
        <div className="skeleton h-4 w-96 rounded-lg" />
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="skeleton h-16 rounded-xl" />
          ))}
        </div>
      </div>
    );
  }

  if (error || !procedure) {
    return (
      <div className="p-6">
        <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
          <p className="text-sm text-[#dc2626]">{error || 'Procédure non trouvée'}</p>
        </div>
      </div>
    );
  }

  const foundCount = execution?.matched_documents.filter((m) => m.found).length || 0;
  const totalRequired = procedure.required_documents.length;

  return (
    <div className="p-6 space-y-6 max-w-4xl">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="space-y-2">
          <div className="flex items-center gap-3">
            <button
              onClick={() => router.push('/procedures')}
              className="p-1.5 rounded-lg text-[#6b7280] hover:text-[#1a1a1a] hover:bg-beige-300/60 transition-colors"
            >
              <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M15 10H5" />
                <path d="M10 5L5 10L10 15" />
              </svg>
            </button>
            <h1 className="text-2xl font-bold text-[#1a1a1a]">{procedure.name}</h1>
          </div>
          <div className="flex items-center gap-3 ml-10">
            <ProcedureTypeBadge type={procedure.procedure_type} />
            <span className="text-sm text-[#6b7280]">
              Créée le {new Date(procedure.created_at).toLocaleDateString('fr-FR', {
                day: 'numeric',
                month: 'long',
                year: 'numeric',
              })}
            </span>
          </div>
        </div>

        <div className="flex items-center gap-1">
          <Link
            href={`/procedures/edit?id=${procId}`}
            className="p-2 rounded-lg text-[#6b7280] hover:text-accent hover:bg-accent/10 transition-colors"
            title="Modifier"
          >
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M11 3L15 7L7 15H3V11L11 3Z" />
            </svg>
          </Link>
          <button
            onClick={handleDelete}
            className="p-2 rounded-lg text-[#6b7280] hover:text-[#dc2626] hover:bg-red-50 transition-colors"
            title="Supprimer"
          >
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 5H15" />
              <path d="M7 5V3H11V5" />
              <path d="M5 5L6 15H12L13 5" />
            </svg>
          </button>
        </div>
      </div>

      {/* Description */}
      {procedure.description && (
        <div className="bg-white border border-beige-300/60 rounded-xl p-4">
          <p className="text-sm text-[#1a1a1a]">{procedure.description}</p>
        </div>
      )}

      {/* Remarks */}
      {procedure.remarks && (
        <div className="bg-beige-50 border border-beige-300/60 rounded-xl p-4">
          <p className="text-xs font-medium text-[#6b7280] mb-1">Remarques</p>
          <p className="text-sm text-[#1a1a1a]">{procedure.remarks}</p>
        </div>
      )}

      {/* Required Documents */}
      <div>
        <h2 className="text-lg font-semibold text-[#1a1a1a] mb-3">
          Documents requis ({totalRequired})
        </h2>
        <div className="space-y-2">
          {procedure.required_documents.map((doc, i) => (
            <div
              key={i}
              className="bg-white border border-beige-300/60 rounded-xl p-4 flex items-start gap-3"
            >
              <span className="w-7 h-7 bg-accent/10 text-accent rounded-full flex items-center justify-center text-xs font-bold flex-shrink-0 mt-0.5">
                {i + 1}
              </span>
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <TypeBadge type={doc.doc_type} />
                  <span className="text-sm font-medium text-[#1a1a1a]">{doc.label}</span>
                </div>
                {doc.description && (
                  <p className="text-xs text-[#6b7280]">{doc.description}</p>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Execute section */}
      <div className="border-t border-beige-300 pt-6">
        {!showExecute && !execution && (
          <button
            onClick={() => setShowExecute(true)}
            className="flex items-center gap-2 px-6 py-3 bg-accent hover:bg-accent-hover text-white rounded-xl text-sm font-medium transition-colors"
          >
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <polygon points="6,3 15,9 6,15" fill="currentColor" stroke="none" />
            </svg>
            Lancer la procédure
          </button>
        )}

        {showExecute && !execution && (
          <div className="bg-white border border-beige-300/60 rounded-xl p-5 space-y-4">
            <div>
              <h3 className="text-sm font-semibold text-[#1a1a1a] mb-1">Lancer la procédure</h3>
              <p className="text-xs text-[#6b7280]">
                Indiquez le nom de la personne concernée. Le système recherchera automatiquement les documents les plus récents correspondants.
              </p>
            </div>

            <div className="flex gap-3">
              <input
                type="text"
                value={personName}
                onChange={(e) => setPersonName(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') handleExecute();
                }}
                placeholder="Nom et prénom de la personne..."
                className="flex-1 px-4 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent"
                disabled={executing}
              />
              <button
                onClick={handleExecute}
                disabled={!personName.trim() || executing}
                className="px-5 py-2.5 bg-accent hover:bg-accent-hover text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
              >
                {executing ? (
                  <>
                    <svg className="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                    </svg>
                    Recherche...
                  </>
                ) : (
                  'Rechercher'
                )}
              </button>
            </div>

            {executing && (
              <div className="bg-beige-50 rounded-lg p-3">
                <p className="text-xs text-[#6b7280] flex items-center gap-2">
                  <svg className="animate-spin h-3 w-3" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                  </svg>
                  L&apos;IA analyse vos documents pour trouver les meilleures correspondances...
                </p>
              </div>
            )}

            {execError && (
              <div className="p-3 bg-red-50 border border-red-200 rounded-lg">
                <p className="text-xs text-[#dc2626]">{execError}</p>
              </div>
            )}

            <button
              onClick={() => {
                setShowExecute(false);
                setPersonName('');
                setExecError(null);
              }}
              className="text-xs text-[#6b7280] hover:text-[#1a1a1a] transition-colors"
            >
              Annuler
            </button>
          </div>
        )}

        {/* Execution results */}
        {execution && (
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-lg font-semibold text-[#1a1a1a]">
                  Résultats pour « {execution.person_name} »
                </h3>
                <p className="text-sm text-[#6b7280]">
                  {foundCount}/{totalRequired} document{foundCount !== 1 ? 's' : ''} trouvé{foundCount !== 1 ? 's' : ''}
                </p>
              </div>
              <button
                onClick={() => {
                  setExecution(null);
                  setShowExecute(true);
                  setPersonName('');
                }}
                className="px-4 py-2 bg-white border border-beige-300 text-[#1a1a1a] rounded-lg text-sm font-medium hover:bg-beige-50 transition-colors"
              >
                Nouvelle recherche
              </button>
            </div>

            {/* Progress bar */}
            <div className="bg-beige-200 rounded-full h-2 overflow-hidden">
              <div
                className={`h-full rounded-full transition-all ${
                  foundCount === totalRequired ? 'bg-green-500' : foundCount > 0 ? 'bg-amber-500' : 'bg-red-400'
                }`}
                style={{ width: `${totalRequired > 0 ? (foundCount / totalRequired) * 100 : 0}%` }}
              />
            </div>

            {/* Results list */}
            <div className="space-y-3">
              {execution.matched_documents.map((match, i) => (
                <MatchedDocumentRow key={i} match={match} />
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// Matched document row component
function MatchedDocumentRow({ match }: { match: MatchedDocument }) {
  return (
    <div
      className={`bg-white border rounded-xl p-4 ${
        match.found ? 'border-green-200' : 'border-red-200'
      }`}
    >
      <div className="flex items-start gap-3">
        {/* Status icon */}
        <div className={`w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 ${
          match.found ? 'bg-green-100' : 'bg-red-100'
        }`}>
          {match.found ? (
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="#059669" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 8L6.5 11.5L13 5" />
            </svg>
          ) : (
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="#dc2626" strokeWidth="2" strokeLinecap="round">
              <path d="M4 4L12 12" />
              <path d="M12 4L4 12" />
            </svg>
          )}
        </div>

        <div className="flex-1 min-w-0">
          {/* Required doc info */}
          <div className="flex items-center gap-2 mb-1">
            <TypeBadge type={match.required_doc_type} />
            <span className="text-sm font-medium text-[#1a1a1a]">{match.required_label}</span>
          </div>

          {/* Found document details */}
          {match.found && match.document ? (
            <div className="mt-2 bg-beige-50 rounded-lg p-3 space-y-1">
              <p className="text-sm font-medium text-[#1a1a1a]">
                {match.document.title || match.document.filename}
              </p>
              <div className="flex flex-wrap items-center gap-3 text-xs text-[#6b7280]">
                {match.document.emetteur && (
                  <span>Émetteur : {match.document.emetteur}</span>
                )}
                {match.document.doc_date && (
                  <span>Date : {new Date(match.document.doc_date).toLocaleDateString('fr-FR')}</span>
                )}
                {match.document.destinataire && (
                  <span>Destinataire : {match.document.destinataire}</span>
                )}
              </div>
              {match.document.resume && (
                <p className="text-xs text-[#6b7280] line-clamp-2">{match.document.resume}</p>
              )}

              {/* Action buttons */}
              <div className="flex gap-2 mt-2">
                <a
                  href={getDocumentFileUrl(match.document.id)}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-white border border-beige-300 rounded-lg text-xs font-medium text-[#1a1a1a] hover:bg-beige-50 transition-colors"
                >
                  <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M1 6C1 6 3 2 6 2C9 2 11 6 11 6C11 6 9 10 6 10C3 10 1 6 1 6Z" />
                    <circle cx="6" cy="6" r="1.5" />
                  </svg>
                  Visualiser
                </a>
                <a
                  href={getDocumentFileUrl(match.document.id)}
                  download
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-accent text-white rounded-lg text-xs font-medium hover:bg-accent-hover transition-colors"
                >
                  <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M6 2V8" />
                    <path d="M3 6L6 9L9 6" />
                    <path d="M2 10H10" />
                  </svg>
                  Télécharger
                </a>
              </div>
            </div>
          ) : (
            <p className="text-xs text-[#dc2626] mt-1">
              Aucun document correspondant trouvé
            </p>
          )}
        </div>
      </div>
    </div>
  );
}

export default function ProcedureViewPage() {
  return (
    <Suspense fallback={
      <div className="p-6 space-y-6">
        <div className="skeleton h-8 w-64 rounded-lg" />
        <div className="skeleton h-4 w-96 rounded-lg" />
        <div className="space-y-3">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="skeleton h-16 rounded-xl" />
          ))}
        </div>
      </div>
    }>
      <ProcedureDetailContent />
    </Suspense>
  );
}
