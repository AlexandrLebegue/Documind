'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  acceptIngestMark,
  getIngestMarks,
  reevaluateIngestMark,
  rejectIngestMark,
} from '@/lib/api';
import type { IngestMark, IngestMarksResponse } from '@/lib/api';
import { toast } from '@/components/Toast';

const FILTERS = [
  { value: '', label: 'Tous' },
  { value: 'pending', label: 'À valider' },
  { value: 'accepted', label: 'Acceptés' },
  { value: 'rejected', label: 'Refusés' },
  { value: 'error', label: 'Erreurs' },
];

function VerdictBadge({ verdict }: { verdict: IngestMark['verdict'] }) {
  const styles: Record<string, string> = {
    pending: 'bg-amber-50 text-amber-700 border-amber-200',
    accepted: 'bg-green-50 text-green-700 border-green-200',
    rejected: 'bg-red-50 text-red-700 border-red-200',
    error: 'bg-gray-100 text-gray-700 border-gray-200',
  };
  const labels: Record<string, string> = {
    pending: 'À valider',
    accepted: 'Accepté',
    rejected: 'Refusé',
    error: 'Erreur',
  };
  return (
    <span className={`inline-flex rounded-full border px-2.5 py-0.5 text-xs font-medium ${styles[verdict] || styles.error}`}>
      {labels[verdict] || verdict}
    </span>
  );
}

function formatDate(value?: string) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' });
}

export default function SyncPage() {
  const [data, setData] = useState<IngestMarksResponse | null>(null);
  const [filter, setFilter] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const load = useCallback(async (showSpinner = false) => {
    if (showSpinner) setLoading(true);
    try {
      const result = await getIngestMarks({ verdict: filter || undefined, limit: 100 });
      setData(result);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur de chargement');
    } finally {
      setLoading(false);
    }
  }, [filter]);

  useEffect(() => {
    load(true);
    const timer = setInterval(() => load(false), 5000);
    return () => clearInterval(timer);
  }, [load]);

  const act = async (sha256: string, action: 'accept' | 'reject' | 'reevaluate') => {
    setBusy(sha256);
    try {
      if (action === 'accept') {
        await acceptIngestMark(sha256);
        toast('Acceptation mise en file de traitement', 'success');
      } else if (action === 'reject') {
        await rejectIngestMark(sha256);
        toast('Fichier refusé', 'success');
      } else {
        await reevaluateIngestMark(sha256);
        toast('Réévaluation demandée', 'success');
      }
      await load(false);
    } catch (err) {
      toast(err instanceof Error ? err.message : 'Action impossible', 'error');
    } finally {
      setBusy(null);
    }
  };

  const marks = data?.marks || [];
  const summary = useMemo(() => {
    const counts = data?.counts || {};
    return [
      { label: 'À valider', value: counts.pending || 0, color: 'text-amber-600' },
      { label: 'Acceptés', value: counts.accepted || 0, color: 'text-green-600' },
      { label: 'Refusés', value: counts.rejected || 0, color: 'text-red-600' },
      { label: 'Erreurs', value: counts.error || 0, color: 'text-gray-600' },
    ];
  }, [data]);

  return (
    <div className="p-4 sm:p-6 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#1a1a1a]">Synchronisation</h1>
        <p className="mt-1 text-sm text-[#6b7280]">
          Fichiers reçus des dossiers surveillés, verdicts du juge et validation manuelle.
        </p>
      </div>

      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        {summary.map((item) => (
          <div key={item.label} className="rounded-xl border border-beige-300 bg-white p-4 shadow-sm">
            <p className="text-xs uppercase tracking-wide text-[#6b7280]">{item.label}</p>
            <p className={`mt-1 text-2xl font-bold ${item.color}`}>{item.value}</p>
          </div>
        ))}
      </div>

      <div className="flex flex-wrap gap-2">
        {FILTERS.map((item) => (
          <button
            key={item.value}
            onClick={() => setFilter(item.value)}
            className={`min-h-[44px] rounded-lg px-4 text-sm font-medium transition ${
              filter === item.value
                ? 'bg-accent text-white'
                : 'bg-white text-[#1a1a1a] border border-beige-300 hover:bg-beige-50'
            }`}
          >
            {item.label}
          </button>
        ))}
      </div>

      {error && (
        <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700">{error}</div>
      )}

      {loading && !data ? (
        <div className="space-y-2">
          {[...Array(5)].map((_, index) => (
            <div key={index} className="skeleton h-20 rounded-xl" />
          ))}
        </div>
      ) : marks.length === 0 ? (
        <div className="rounded-xl border border-beige-300 bg-white p-10 text-center text-sm text-[#6b7280]">
          Aucun fichier pour ce filtre. Le client PC envoie les nouveaux fichiers selon l&apos;intervalle configuré.
        </div>
      ) : (
        <div className="space-y-3">
          {marks.map((mark) => (
            <div key={mark.sha256} className="rounded-xl border border-beige-300 bg-white p-4 shadow-sm">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-2">
                    <p className="truncate font-medium text-[#1a1a1a]">{mark.filename || mark.title || mark.sha256.slice(0, 12)}</p>
                    <VerdictBadge verdict={mark.verdict} />
                    {mark.confidence !== undefined && mark.confidence !== null && (
                      <span className="text-xs text-[#6b7280]">confiance {Math.round(mark.confidence * 100)}%</span>
                    )}
                  </div>
                  <p className="mt-1 text-sm text-[#4b5563]">{mark.reason || '—'}</p>
                  <p className="mt-1 break-all text-xs text-[#9ca3af]">
                    {mark.source || 'machine inconnue'} · {formatDate(mark.first_seen)}
                    {mark.origin_path ? ` · ${mark.origin_path}` : ''}
                  </p>
                  <p className="mt-0.5 font-mono text-[10px] text-[#b8a99a]">{mark.sha256}</p>
                </div>
                <div className="flex flex-wrap gap-2">
                  {mark.verdict === 'pending' && (
                    <>
                      <button
                        disabled={busy === mark.sha256}
                        onClick={() => act(mark.sha256, 'accept')}
                        className="min-h-[40px] rounded-lg bg-green-600 px-4 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-60"
                      >
                        Accepter
                      </button>
                      <button
                        disabled={busy === mark.sha256}
                        onClick={() => act(mark.sha256, 'reject')}
                        className="min-h-[40px] rounded-lg bg-red-600 px-4 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-60"
                      >
                        Refuser
                      </button>
                    </>
                  )}
                  {mark.verdict !== 'pending' && (
                    <button
                      disabled={busy === mark.sha256}
                      onClick={() => act(mark.sha256, 'reevaluate')}
                      className="min-h-[40px] rounded-lg border border-beige-300 px-4 text-sm font-medium text-[#1a1a1a] hover:bg-beige-50 disabled:opacity-60"
                    >
                      Réévaluer
                    </button>
                  )}
                  {mark.doc_id && (
                    <a
                      href={`/documents/view?id=${mark.doc_id}`}
                      className="flex min-h-[40px] items-center rounded-lg border border-beige-300 px-4 text-sm font-medium text-[#1a1a1a] hover:bg-beige-50"
                    >
                      Ouvrir
                    </a>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
