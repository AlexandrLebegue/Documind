'use client';

import { useState, useEffect, useCallback, Suspense } from 'react';
import { useSearchParams } from 'next/navigation';
import { getDocuments } from '@/lib/api';
import type { Document } from '@/lib/api';
import SearchBar from '@/components/SearchBar';
import DocumentCard from '@/components/DocumentCard';
import UploadModal from '@/components/UploadModal';
import { DOC_TYPES } from '@/components/TypeBadge';

function DocumentsContent() {
  const searchParams = useSearchParams();
  const initialQuery = searchParams.get('q') || '';

  const [documents, setDocuments] = useState<Document[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [uploadOpen, setUploadOpen] = useState(false);

  // Filters
  const [query, setQuery] = useState(initialQuery);
  const [docType, setDocType] = useState('');
  const [sortBy, setSortBy] = useState<'newest' | 'oldest' | 'name' | 'type'>('newest');
  const [view, setView] = useState<'grid' | 'list'>('grid');
  const [offset, setOffset] = useState(0);
  const limit = 24;

  const fetchDocs = useCallback(async (reset = true) => {
    if (reset) {
      setLoading(true);
      setOffset(0);
    } else {
      setLoadingMore(true);
    }
    setError(null);

    try {
      const currentOffset = reset ? 0 : offset + limit;
      const params: Record<string, string | number> = {
        limit,
        offset: currentOffset,
      };
      if (query) params.q = query;
      if (docType) params.doc_type = docType;

      const res = await getDocuments(params);

      // Client-side sort
      let sorted = [...res.documents];
      switch (sortBy) {
        case 'newest':
          sorted.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
          break;
        case 'oldest':
          sorted.sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());
          break;
        case 'name':
          sorted.sort((a, b) => a.filename.localeCompare(b.filename, 'fr'));
          break;
        case 'type':
          sorted.sort((a, b) => (a.doc_type || '').localeCompare(b.doc_type || '', 'fr'));
          break;
      }

      if (reset) {
        setDocuments(sorted);
      } else {
        setDocuments((prev) => [...prev, ...sorted]);
      }
      setTotal(res.total);
      setOffset(currentOffset);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur de chargement');
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [query, docType, sortBy, offset, limit]);

  // Initial fetch and re-fetch on filter change
  useEffect(() => {
    fetchDocs(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [query, docType, sortBy]);

  const handleSearch = (q: string) => {
    setQuery(q);
  };

  const hasMore = documents.length < total;

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-[#1a1a1a]">Mes documents</h1>
          <p className="text-sm text-[#6b7280] mt-1">
            {total} document{total !== 1 ? 's' : ''}
          </p>
        </div>
        <button
          onClick={() => setUploadOpen(true)}
          className="flex items-center gap-2 px-4 py-2.5 bg-accent hover:bg-accent-hover text-white rounded-lg text-sm font-medium transition-colors"
        >
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <circle cx="9" cy="9" r="7" />
            <path d="M9 6V12" />
            <path d="M6 9H12" />
          </svg>
          Ajouter un document
        </button>
      </div>

      {/* Search bar */}
      <SearchBar
        onSearch={handleSearch}
        placeholder="Rechercher par nom, contenu, émetteur..."
        initialValue={initialQuery}
      />

      {/* Filters row */}
      <div className="flex flex-wrap items-center gap-3">
        {/* Type filter */}
        <select
          value={docType}
          onChange={(e) => setDocType(e.target.value)}
          className="px-3 py-2 text-sm bg-white border border-beige-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-accent/30"
        >
          <option value="">Tous les types</option>
          {DOC_TYPES.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </select>

        {/* Sort */}
        <select
          value={sortBy}
          onChange={(e) => setSortBy(e.target.value as 'newest' | 'oldest' | 'name' | 'type')}
          className="px-3 py-2 text-sm bg-white border border-beige-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-accent/30"
        >
          <option value="newest">Plus récents</option>
          <option value="oldest">Plus anciens</option>
          <option value="name">Nom</option>
          <option value="type">Type</option>
        </select>

        {/* Spacer */}
        <div className="flex-1" />

        {/* View toggle */}
        <div className="flex bg-white border border-beige-300 rounded-lg overflow-hidden">
          <button
            onClick={() => setView('grid')}
            className={`p-2 ${view === 'grid' ? 'bg-accent text-white' : 'text-[#6b7280] hover:bg-beige-100'}`}
            title="Vue grille"
          >
            <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
              <rect x="1" y="1" width="6" height="6" rx="1" />
              <rect x="9" y="1" width="6" height="6" rx="1" />
              <rect x="1" y="9" width="6" height="6" rx="1" />
              <rect x="9" y="9" width="6" height="6" rx="1" />
            </svg>
          </button>
          <button
            onClick={() => setView('list')}
            className={`p-2 ${view === 'list' ? 'bg-accent text-white' : 'text-[#6b7280] hover:bg-beige-100'}`}
            title="Vue liste"
          >
            <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor">
              <rect x="1" y="2" width="14" height="3" rx="1" />
              <rect x="1" y="7" width="14" height="3" rx="1" />
              <rect x="1" y="12" width="14" height="3" rx="1" />
            </svg>
          </button>
        </div>
      </div>

      {/* Loading */}
      {loading && (
        <div className={view === 'grid' ? 'grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4' : 'space-y-3'}>
          {[...Array(6)].map((_, i) => (
            <div key={i} className={`skeleton ${view === 'grid' ? 'h-48' : 'h-16'} rounded-xl`} />
          ))}
        </div>
      )}

      {/* Error */}
      {error && !loading && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-center">
          <p className="text-[#dc2626] text-sm">{error}</p>
          <button
            onClick={() => fetchDocs(true)}
            className="mt-2 text-sm text-accent hover:text-accent-hover font-medium"
          >
            Réessayer
          </button>
        </div>
      )}

      {/* Empty state */}
      {!loading && !error && documents.length === 0 && (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <div className="w-20 h-20 bg-beige-200 rounded-full flex items-center justify-center mb-4">
            <svg width="36" height="36" viewBox="0 0 56 56" fill="none" stroke="#6b7280" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M14 10H32L42 20V46H14V10Z" />
              <path d="M32 10V20H42" />
              <path d="M22 28H34" />
              <path d="M22 34H30" />
            </svg>
          </div>
          <p className="text-[#1a1a1a] font-medium text-lg mb-1">Aucun document</p>
          <p className="text-sm text-[#6b7280] max-w-md mb-6">
            {query || docType
              ? 'Aucun résultat pour ces critères de recherche'
              : 'Commencez par ajouter votre premier document pour l\'analyser avec DocuMind.'}
          </p>
          {!query && !docType && (
            <button
              onClick={() => setUploadOpen(true)}
              className="flex items-center gap-2 px-4 py-2.5 bg-accent hover:bg-accent-hover text-white rounded-lg text-sm font-medium transition-colors"
            >
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <circle cx="9" cy="9" r="7" />
                <path d="M9 6V12" />
                <path d="M6 9H12" />
              </svg>
              Ajouter un document
            </button>
          )}
        </div>
      )}

      {/* Document grid/list */}
      {!loading && !error && documents.length > 0 && (
        <>
          {view === 'grid' ? (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {documents.map((doc) => (
                <DocumentCard key={doc.id} document={doc} view="grid" />
              ))}
            </div>
          ) : (
            <div className="space-y-3">
              {documents.map((doc) => (
                <DocumentCard key={doc.id} document={doc} view="list" />
              ))}
            </div>
          )}

          {/* Load more */}
          {hasMore && (
            <div className="text-center pt-4">
              <button
                onClick={() => fetchDocs(false)}
                disabled={loadingMore}
                className="px-6 py-2.5 text-sm bg-white border border-beige-300 rounded-lg hover:bg-beige-50 font-medium text-[#1a1a1a] disabled:opacity-50"
              >
                {loadingMore ? (
                  <span className="flex items-center gap-2">
                    <span className="w-4 h-4 border-2 border-beige-300 border-t-accent rounded-full animate-spin" />
                    Chargement...
                  </span>
                ) : (
                  `Charger plus (${documents.length}/${total})`
                )}
              </button>
            </div>
          )}
        </>
      )}

      <UploadModal
        isOpen={uploadOpen}
        onClose={() => setUploadOpen(false)}
        onUploadComplete={() => {
          setUploadOpen(false);
          fetchDocs(true);
        }}
      />
    </div>
  );
}

export default function DocumentsPage() {
  return (
    <Suspense fallback={
      <div className="p-6 space-y-6">
        <div className="skeleton h-8 w-48" />
        <div className="skeleton h-12 w-full rounded-xl" />
        <div className="grid grid-cols-3 gap-4">
          {[...Array(6)].map((_, i) => (
            <div key={i} className="skeleton h-48 rounded-xl" />
          ))}
        </div>
      </div>
    }>
      <DocumentsContent />
    </Suspense>
  );
}
