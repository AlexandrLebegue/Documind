'use client';

import { useState, useEffect, useCallback } from 'react';
import Link from 'next/link';
import { getProcedures, deleteProcedure } from '@/lib/api';
import type { Procedure } from '@/lib/api';
import ProcedureCard from '@/components/ProcedureCard';
import { PROCEDURE_TYPES } from '@/components/ProcedureTypeBadge';

export default function ProceduresPage() {
  const [procedures, setProcedures] = useState<Procedure[]>([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filterType, setFilterType] = useState('');
  const [offset, setOffset] = useState(0);
  const limit = 24;

  const fetchProcedures = useCallback(async (reset = true) => {
    if (reset) {
      setLoading(true);
      setOffset(0);
    }
    setError(null);

    try {
      const currentOffset = reset ? 0 : offset + limit;
      const res = await getProcedures({ limit, offset: currentOffset });

      let filtered = res.procedures;
      if (filterType) {
        filtered = filtered.filter((p) => p.procedure_type === filterType);
      }

      if (reset) {
        setProcedures(filtered);
      } else {
        setProcedures((prev) => [...prev, ...filtered]);
      }
      setTotal(res.total);
      setOffset(currentOffset);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur de chargement');
    } finally {
      setLoading(false);
    }
  }, [filterType, offset, limit]);

  useEffect(() => {
    fetchProcedures(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filterType]);

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer cette procédure ?')) return;
    try {
      await deleteProcedure(id);
      fetchProcedures(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur lors de la suppression');
    }
  };

  const hasMore = procedures.length < total;

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-[#1a1a1a]">Mes procédures</h1>
          <p className="text-sm text-[#6b7280] mt-1">
            {total} procédure{total !== 1 ? 's' : ''}
          </p>
        </div>
        <Link
          href="/procedures/new"
          className="flex items-center gap-2 px-4 py-2.5 bg-accent hover:bg-accent-hover text-white rounded-lg text-sm font-medium transition-colors"
        >
          <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
            <circle cx="9" cy="9" r="7" />
            <path d="M9 6V12" />
            <path d="M6 9H12" />
          </svg>
          Nouvelle procédure
        </Link>
      </div>

      {/* Filter bar */}
      <div className="flex items-center gap-3">
        <select
          value={filterType}
          onChange={(e) => setFilterType(e.target.value)}
          className="px-3 py-2 bg-white border border-beige-300 rounded-lg text-sm text-[#1a1a1a] focus:outline-none focus:ring-2 focus:ring-accent/30"
        >
          <option value="">Tous les types</option>
          {PROCEDURE_TYPES.map((t) => (
            <option key={t.value} value={t.value}>
              {t.label}
            </option>
          ))}
        </select>
      </div>

      {/* Error */}
      {error && (
        <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
          <p className="text-sm text-[#dc2626]">{error}</p>
        </div>
      )}

      {/* Loading */}
      {loading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {[...Array(6)].map((_, i) => (
            <div key={i} className="skeleton h-36 rounded-xl" />
          ))}
        </div>
      ) : procedures.length === 0 ? (
        /* Empty state */
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <div className="w-20 h-20 bg-beige-200 rounded-full flex items-center justify-center mb-4">
            <svg width="36" height="36" viewBox="0 0 36 36" fill="none" stroke="#6b7280" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M10 5H26C28 5 29 7 29 7V29C29 29 28 31 26 31H10C8 31 7 29 7 29V7C7 5 10 5 10 5Z" />
              <path d="M13 12H23" />
              <path d="M13 17H23" />
              <path d="M13 22H19" />
            </svg>
          </div>
          <p className="text-[#1a1a1a] font-medium text-lg mb-1">Aucune procédure</p>
          <p className="text-sm text-[#6b7280] max-w-md mb-6">
            Créez votre première procédure pour rassembler les documents nécessaires à vos démarches.
          </p>
          <Link
            href="/procedures/new"
            className="flex items-center gap-2 px-4 py-2.5 bg-accent hover:bg-accent-hover text-white rounded-lg text-sm font-medium transition-colors"
          >
            <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <circle cx="9" cy="9" r="7" />
              <path d="M9 6V12" />
              <path d="M6 9H12" />
            </svg>
            Créer une procédure
          </Link>
        </div>
      ) : (
        /* Grid */
        <>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {procedures.map((proc) => (
              <ProcedureCard key={proc.id} procedure={proc} />
            ))}
          </div>

          {/* Load more */}
          {hasMore && (
            <div className="flex justify-center pt-4">
              <button
                onClick={() => fetchProcedures(false)}
                className="px-6 py-2.5 bg-white border border-beige-300 rounded-lg text-sm font-medium text-[#1a1a1a] hover:bg-beige-50 transition-colors"
              >
                Charger plus
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
