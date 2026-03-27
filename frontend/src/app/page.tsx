'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { getStats, getHealth, getAlerts, dismissAlert } from '@/lib/api';
import type { Stats, Health, AlertItem } from '@/lib/api';
import SearchBar from '@/components/SearchBar';
import StatsCards from '@/components/StatsCards';
import DocumentCard from '@/components/DocumentCard';
import PieChart from '@/components/PieChart';
import AlertBadge from '@/components/AlertBadge';

export default function DashboardPage() {
  const router = useRouter();
  const [stats, setStats] = useState<Stats | null>(null);
  const [health, setHealth] = useState<Health | null>(null);
  const [alerts, setAlerts] = useState<AlertItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    async function fetchData() {
      try {
        const [statsData, healthData, alertsData] = await Promise.all([
          getStats(),
          getHealth(),
          getAlerts({ days_ahead: 90, limit: 5 }).catch(() => ({ alerts: [] })),
        ]);
        setStats(statsData);
        setHealth(healthData);
        setAlerts(alertsData.alerts || []);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erreur de chargement');
      } finally {
        setLoading(false);
      }
    }
    fetchData();
  }, []);

  const handleSearch = (query: string) => {
    if (query.trim()) {
      router.push(`/documents?q=${encodeURIComponent(query.trim())}`);
    }
  };

  if (loading) {
    return (
      <div className="p-6 space-y-6">
        {/* Skeleton header */}
        <div className="space-y-2">
          <div className="skeleton h-8 w-48" />
          <div className="skeleton h-4 w-72" />
        </div>
        {/* Skeleton search */}
        <div className="skeleton h-12 w-full rounded-xl" />
        {/* Skeleton stat cards */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
          {[...Array(4)].map((_, i) => (
            <div key={i} className="skeleton h-20 rounded-xl" />
          ))}
        </div>
        {/* Skeleton content */}
        <div className="grid grid-cols-3 gap-6">
          <div className="col-span-2 space-y-3">
            {[...Array(5)].map((_, i) => (
              <div key={i} className="skeleton h-20 rounded-xl" />
            ))}
          </div>
          <div className="skeleton h-80 rounded-xl" />
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-6">
        <div className="bg-red-50 border border-red-200 rounded-xl p-6 text-center">
          <svg width="40" height="40" viewBox="0 0 40 40" fill="none" stroke="#dc2626" strokeWidth="1.5" strokeLinecap="round" className="mx-auto mb-3">
            <circle cx="20" cy="20" r="16" />
            <path d="M20 14V22" />
            <circle cx="20" cy="27" r="1" fill="#dc2626" />
          </svg>
          <p className="text-[#dc2626] font-medium">Erreur de connexion au serveur</p>
          <p className="text-sm text-[#6b7280] mt-1">{error}</p>
          <button
            onClick={() => window.location.reload()}
            className="mt-3 px-4 py-2 text-sm bg-accent hover:bg-accent-hover text-white rounded-lg"
          >
            Réessayer
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-[#1a1a1a]">Tableau de bord</h1>
        <p className="text-sm text-[#6b7280] mt-1">Vue d&apos;ensemble de vos documents</p>
      </div>

      {/* Search bar */}
      <SearchBar
        onSearch={handleSearch}
        placeholder="Rechercher dans vos documents..."
        large
      />

      {/* Stats cards */}
      <StatsCards stats={stats} health={health} />

      {/* Expiring Soon Widget */}
      {alerts.length > 0 && (
        <div className="bg-white rounded-xl border border-amber-200 shadow-sm overflow-hidden">
          <div className="flex items-center justify-between px-5 py-3 bg-amber-50 border-b border-amber-200">
            <div className="flex items-center gap-2">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#d97706" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 3L21 19H3L12 3Z" />
                <path d="M12 10V14" />
                <circle cx="12" cy="17" r="0.5" fill="#d97706" />
              </svg>
              <h2 className="text-sm font-semibold text-amber-800">Documents à surveiller</h2>
            </div>
            <Link href="/alerts" className="text-xs text-amber-700 hover:text-amber-900 font-medium">
              Voir toutes les alertes →
            </Link>
          </div>
          <div className="divide-y divide-beige-200">
            {alerts.slice(0, 5).map((alert) => (
              <div
                key={`${alert.alert_type}-${alert.document.id}`}
                className="flex items-center gap-4 px-5 py-3 hover:bg-beige-50 transition-colors group"
              >
                <Link
                  href={`/documents/view?id=${alert.document.id}`}
                  className="flex-1 min-w-0"
                >
                  <p className="text-sm font-medium text-[#1a1a1a] truncate">
                    {alert.document.title || alert.document.filename}
                  </p>
                  <p className="text-xs text-[#6b7280]">
                    {alert.alert_type === 'expiration' ? 'Expire' : 'Échéance'} le{' '}
                    {new Date(alert.target_date).toLocaleDateString('fr-FR', {
                      day: 'numeric',
                      month: 'short',
                      year: 'numeric',
                    })}
                    {alert.days_remaining < 0
                      ? ` (il y a ${Math.abs(alert.days_remaining)} jours)`
                      : alert.days_remaining === 0
                        ? ' (aujourd\'hui)'
                        : ` (dans ${alert.days_remaining} jours)`}
                  </p>
                </Link>
                <AlertBadge
                  urgency={alert.urgency}
                  label={
                    alert.days_remaining < 0
                      ? (alert.alert_type === 'expiration' ? 'Expiré' : 'En retard')
                      : alert.urgency === 'critical'
                        ? 'Urgent'
                        : alert.urgency === 'warning'
                          ? 'Bientôt'
                          : 'À surveiller'
                  }
                />
                <button
                  onClick={async () => {
                    try {
                      await dismissAlert(alert.document.id, alert.alert_type as 'expiration' | 'echeance');
                      setAlerts((prev) => prev.filter(
                        (a) => !(a.document.id === alert.document.id && a.alert_type === alert.alert_type)
                      ));
                    } catch (err) {
                      console.error('Failed to dismiss alert:', err);
                    }
                  }}
                  className="flex-shrink-0 p-1 rounded-md text-[#9ca3af] hover:text-red-500 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-all"
                  title="Supprimer cette alerte"
                >
                  <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                    <path d="M3 3L11 11" />
                    <path d="M11 3L3 11" />
                  </svg>
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Two-column layout */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Recent documents */}
        <div className="lg:col-span-2">
          <h2 className="text-lg font-semibold text-[#1a1a1a] mb-4">Documents récents</h2>
          {stats?.recent_documents && stats.recent_documents.length > 0 ? (
            <div className="space-y-3">
              {stats.recent_documents.slice(0, 10).map((doc) => (
                <DocumentCard key={doc.id} document={doc} view="list" />
              ))}
            </div>
          ) : (
            <div className="bg-white rounded-xl border border-beige-300/50 p-8 text-center">
              <svg width="48" height="48" viewBox="0 0 48 48" fill="none" stroke="#6b7280" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" className="mx-auto mb-3">
                <path d="M12 8H28L36 16V40H12V8Z" />
                <path d="M28 8V16H36" />
              </svg>
              <p className="text-[#6b7280] font-medium">Aucun document</p>
              <p className="text-sm text-[#6b7280] mt-1">Commencez par ajouter un document via le bouton dans la barre latérale</p>
            </div>
          )}
        </div>

        {/* Pie chart */}
        <div>
          <h2 className="text-lg font-semibold text-[#1a1a1a] mb-4">Répartition par type</h2>
          <div className="bg-white rounded-xl border border-beige-300/50 p-5 shadow-sm">
            <PieChart data={stats?.count_by_type || {}} />
          </div>
        </div>
      </div>
    </div>
  );
}
