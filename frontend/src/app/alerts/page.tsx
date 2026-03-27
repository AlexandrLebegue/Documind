'use client';

import { useState, useEffect } from 'react';
import Link from 'next/link';
import { getAlerts, getRenewalSuggestions, getGapAlerts, dismissAlert } from '@/lib/api';
import type { AlertItem, RenewalSuggestion, GapAlert } from '@/lib/api';
import AlertBadge from '@/components/AlertBadge';
import TypeBadge from '@/components/TypeBadge';

type UrgencyFilter = 'all' | 'critical' | 'warning' | 'info';
type TypeFilter = 'all' | 'expiration' | 'echeance';
type TabFilter = 'alerts' | 'suggestions' | 'gaps';

export default function AlertsPage() {
  const [alerts, setAlerts] = useState<AlertItem[]>([]);
  const [suggestions, setSuggestions] = useState<RenewalSuggestion[]>([]);
  const [gaps, setGaps] = useState<GapAlert[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Summary counts
  const [overdueCount, setOverdueCount] = useState(0);
  const [expiringCount, setExpiringCount] = useState(0);
  const [paymentsCount, setPaymentsCount] = useState(0);

  // Filters
  const [urgencyFilter, setUrgencyFilter] = useState<UrgencyFilter>('all');
  const [typeFilter, setTypeFilter] = useState<TypeFilter>('all');
  const [activeTab, setActiveTab] = useState<TabFilter>('alerts');

  useEffect(() => {
    async function fetchData() {
      try {
        const [alertsData, suggestionsData, gapsData] = await Promise.all([
          getAlerts({ days_ahead: 365, limit: 100 }),
          getRenewalSuggestions().catch(() => ({ suggestions: [] })),
          getGapAlerts().catch(() => ({ gaps: [], total: 0 })),
        ]);
        setAlerts(alertsData.alerts || []);
        setOverdueCount(alertsData.overdue_count || 0);
        setExpiringCount(alertsData.expiring_count || 0);
        setPaymentsCount(alertsData.upcoming_payments || 0);
        setSuggestions(suggestionsData.suggestions || []);
        setGaps(gapsData.gaps || []);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erreur de chargement');
      } finally {
        setLoading(false);
      }
    }
    fetchData();
  }, []);

  // Filter alerts
  const filteredAlerts = alerts.filter((a) => {
    if (urgencyFilter !== 'all' && a.urgency !== urgencyFilter) return false;
    if (typeFilter !== 'all' && a.alert_type !== typeFilter) return false;
    return true;
  });

  if (loading) {
    return (
      <div className="p-6 space-y-6">
        <div className="skeleton h-8 w-48" />
        <div className="grid grid-cols-3 gap-4">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="skeleton h-20 rounded-xl" />
          ))}
        </div>
        <div className="skeleton h-12 rounded-xl" />
        {[...Array(5)].map((_, i) => (
          <div key={i} className="skeleton h-16 rounded-xl" />
        ))}
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-6">
        <div className="bg-red-50 border border-red-200 rounded-xl p-6 text-center">
          <p className="text-[#dc2626] font-medium">Erreur de chargement</p>
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
        <h1 className="text-2xl font-bold text-[#1a1a1a]">Alertes</h1>
        <p className="text-sm text-[#6b7280] mt-1">Suivi des expirations, échéances et documents manquants</p>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className={`rounded-xl border p-4 shadow-sm ${overdueCount > 0 ? 'bg-red-50 border-red-200' : 'bg-white border-beige-300/50'}`}>
          <div className="flex items-center gap-3">
            <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${overdueCount > 0 ? 'bg-red-100' : 'bg-beige-100'}`}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={overdueCount > 0 ? '#dc2626' : '#6b7280'} strokeWidth="2" strokeLinecap="round">
                <circle cx="12" cy="12" r="9" />
                <path d="M15 9L9 15" />
                <path d="M9 9L15 15" />
              </svg>
            </div>
            <div>
              <p className="text-xs text-[#6b7280] font-medium">Expirés</p>
              <p className={`text-lg font-bold ${overdueCount > 0 ? 'text-red-700' : 'text-[#1a1a1a]'}`}>{overdueCount}</p>
            </div>
          </div>
        </div>

        <div className={`rounded-xl border p-4 shadow-sm ${expiringCount > 0 ? 'bg-amber-50 border-amber-200' : 'bg-white border-beige-300/50'}`}>
          <div className="flex items-center gap-3">
            <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${expiringCount > 0 ? 'bg-amber-100' : 'bg-beige-100'}`}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={expiringCount > 0 ? '#d97706' : '#6b7280'} strokeWidth="2" strokeLinecap="round">
                <path d="M12 3L21 19H3L12 3Z" />
                <path d="M12 10V14" />
                <circle cx="12" cy="17" r="0.5" fill={expiringCount > 0 ? '#d97706' : '#6b7280'} />
              </svg>
            </div>
            <div>
              <p className="text-xs text-[#6b7280] font-medium">Expirent ce mois</p>
              <p className={`text-lg font-bold ${expiringCount > 0 ? 'text-amber-700' : 'text-[#1a1a1a]'}`}>{expiringCount}</p>
            </div>
          </div>
        </div>

        <div className={`rounded-xl border p-4 shadow-sm ${paymentsCount > 0 ? 'bg-blue-50 border-blue-200' : 'bg-white border-beige-300/50'}`}>
          <div className="flex items-center gap-3">
            <div className={`w-10 h-10 rounded-lg flex items-center justify-center ${paymentsCount > 0 ? 'bg-blue-100' : 'bg-beige-100'}`}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={paymentsCount > 0 ? '#2563eb' : '#6b7280'} strokeWidth="2" strokeLinecap="round">
                <circle cx="12" cy="12" r="9" />
                <path d="M12 7V12L15 15" />
              </svg>
            </div>
            <div>
              <p className="text-xs text-[#6b7280] font-medium">Échéances ce mois</p>
              <p className={`text-lg font-bold ${paymentsCount > 0 ? 'text-blue-700' : 'text-[#1a1a1a]'}`}>{paymentsCount}</p>
            </div>
          </div>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 bg-beige-100 rounded-lg p-1">
        {[
          { key: 'alerts' as TabFilter, label: 'Alertes', count: alerts.length },
          { key: 'suggestions' as TabFilter, label: 'Renouvellements', count: suggestions.length },
          { key: 'gaps' as TabFilter, label: 'Documents manquants', count: gaps.length },
        ].map((tab) => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key)}
            className={`flex-1 py-2 px-3 text-sm font-medium rounded-md transition-colors ${
              activeTab === tab.key
                ? 'bg-white text-[#1a1a1a] shadow-sm'
                : 'text-[#6b7280] hover:text-[#1a1a1a]'
            }`}
          >
            {tab.label}
            {tab.count > 0 && (
              <span className={`ml-1.5 text-xs px-1.5 py-0.5 rounded-full ${
                activeTab === tab.key ? 'bg-accent/10 text-accent' : 'bg-beige-200 text-[#6b7280]'
              }`}>
                {tab.count}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Alerts tab */}
      {activeTab === 'alerts' && (
        <div className="space-y-4">
          {/* Filters */}
          <div className="flex flex-wrap gap-2">
            <div className="flex gap-1 bg-beige-50 rounded-lg p-0.5">
              {[
                { key: 'all' as UrgencyFilter, label: 'Toutes' },
                { key: 'critical' as UrgencyFilter, label: 'Urgentes' },
                { key: 'warning' as UrgencyFilter, label: 'Bientôt' },
                { key: 'info' as UrgencyFilter, label: 'À surveiller' },
              ].map((f) => (
                <button
                  key={f.key}
                  onClick={() => setUrgencyFilter(f.key)}
                  className={`px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                    urgencyFilter === f.key
                      ? 'bg-white text-[#1a1a1a] shadow-sm'
                      : 'text-[#6b7280] hover:text-[#1a1a1a]'
                  }`}
                >
                  {f.label}
                </button>
              ))}
            </div>
            <div className="flex gap-1 bg-beige-50 rounded-lg p-0.5">
              {[
                { key: 'all' as TypeFilter, label: 'Tout' },
                { key: 'expiration' as TypeFilter, label: 'Expirations' },
                { key: 'echeance' as TypeFilter, label: 'Échéances' },
              ].map((f) => (
                <button
                  key={f.key}
                  onClick={() => setTypeFilter(f.key)}
                  className={`px-3 py-1.5 text-xs font-medium rounded-md transition-colors ${
                    typeFilter === f.key
                      ? 'bg-white text-[#1a1a1a] shadow-sm'
                      : 'text-[#6b7280] hover:text-[#1a1a1a]'
                  }`}
                >
                  {f.label}
                </button>
              ))}
            </div>
          </div>

          {/* Alert list */}
          {filteredAlerts.length === 0 ? (
            <div className="bg-white rounded-xl border border-beige-300/50 p-8 text-center">
              <svg width="48" height="48" viewBox="0 0 48 48" fill="none" stroke="#059669" strokeWidth="1.5" strokeLinecap="round" className="mx-auto mb-3">
                <circle cx="24" cy="24" r="16" />
                <path d="M16 24L22 30L32 18" />
              </svg>
              <p className="text-[#059669] font-medium">Tout est en ordre !</p>
              <p className="text-sm text-[#6b7280] mt-1">Aucun document ne nécessite votre attention.</p>
            </div>
          ) : (
            <div className="bg-white rounded-xl border border-beige-300/50 overflow-hidden">
              <div className="divide-y divide-beige-200">
                {filteredAlerts.map((alert) => (
                  <div
                    key={`${alert.alert_type}-${alert.document.id}`}
                    className="flex items-center gap-4 px-5 py-4 hover:bg-beige-50 transition-colors group"
                  >
                    {/* Clickable area → document view */}
                    <Link
                      href={`/documents/view?id=${alert.document.id}`}
                      className="flex items-center gap-4 flex-1 min-w-0"
                    >
                      {/* Icon */}
                      <div className={`flex-shrink-0 w-10 h-10 rounded-lg flex items-center justify-center ${
                        alert.urgency === 'critical' ? 'bg-red-100' :
                        alert.urgency === 'warning' ? 'bg-amber-100' : 'bg-blue-100'
                      }`}>
                        {alert.alert_type === 'expiration' ? (
                          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={
                            alert.urgency === 'critical' ? '#dc2626' :
                            alert.urgency === 'warning' ? '#d97706' : '#2563eb'
                          } strokeWidth="2" strokeLinecap="round">
                            <path d="M12 3L21 19H3L12 3Z" />
                            <path d="M12 10V14" />
                            <circle cx="12" cy="17" r="0.5" fill="currentColor" />
                          </svg>
                        ) : (
                          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={
                            alert.urgency === 'critical' ? '#dc2626' :
                            alert.urgency === 'warning' ? '#d97706' : '#2563eb'
                          } strokeWidth="2" strokeLinecap="round">
                            <circle cx="12" cy="12" r="9" />
                            <path d="M12 7V12L15 15" />
                          </svg>
                        )}
                      </div>

                      {/* Info */}
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-0.5">
                          <p className="text-sm font-medium text-[#1a1a1a] truncate">
                            {alert.document.title || alert.document.filename}
                          </p>
                          <TypeBadge type={alert.document.doc_type} />
                        </div>
                        <p className="text-xs text-[#6b7280]">
                          {alert.alert_type === 'expiration' ? 'Expire' : 'Échéance'} le{' '}
                          {new Date(alert.target_date).toLocaleDateString('fr-FR', {
                            day: 'numeric',
                            month: 'long',
                            year: 'numeric',
                          })}
                          {alert.document.emetteur && ` · ${alert.document.emetteur}`}
                        </p>
                      </div>
                    </Link>

                    {/* Days remaining + badge */}
                    <div className="flex-shrink-0 flex items-center gap-3">
                      <span className={`text-sm font-semibold ${
                        alert.days_remaining < 0 ? 'text-red-600' :
                        alert.days_remaining <= 7 ? 'text-red-600' :
                        alert.days_remaining <= 30 ? 'text-amber-600' : 'text-blue-600'
                      }`}>
                        {alert.days_remaining < 0
                          ? `${Math.abs(alert.days_remaining)}j en retard`
                          : alert.days_remaining === 0
                            ? "Aujourd'hui"
                            : `${alert.days_remaining}j`}
                      </span>
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
                        size="md"
                      />
                    </div>

                    {/* Dismiss button */}
                    <button
                      onClick={async (e) => {
                        e.stopPropagation();
                        try {
                          await dismissAlert(alert.document.id, alert.alert_type as 'expiration' | 'echeance');
                          setAlerts((prev) => prev.filter(
                            (a) => !(a.document.id === alert.document.id && a.alert_type === alert.alert_type)
                          ));
                        } catch (err) {
                          console.error('Failed to dismiss alert:', err);
                        }
                      }}
                      className="flex-shrink-0 p-1.5 rounded-lg text-[#9ca3af] hover:text-red-500 hover:bg-red-50 opacity-0 group-hover:opacity-100 transition-all"
                      title="Supprimer cette alerte"
                    >
                      <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                        <path d="M4 4L12 12" />
                        <path d="M12 4L4 12" />
                      </svg>
                    </button>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Suggestions tab */}
      {activeTab === 'suggestions' && (
        <div className="space-y-4">
          {suggestions.length === 0 ? (
            <div className="bg-white rounded-xl border border-beige-300/50 p-8 text-center">
              <svg width="48" height="48" viewBox="0 0 48 48" fill="none" stroke="#6b7280" strokeWidth="1.5" strokeLinecap="round" className="mx-auto mb-3">
                <circle cx="24" cy="24" r="16" />
                <path d="M24 18V26" />
                <circle cx="24" cy="31" r="1" fill="#6b7280" />
              </svg>
              <p className="text-[#6b7280] font-medium">Aucune suggestion de renouvellement</p>
              <p className="text-sm text-[#6b7280] mt-1">
                Les suggestions apparaissent quand des documents expirent dans les 30 prochains jours.
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {suggestions.map((s, idx) => (
                <div
                  key={idx}
                  className="bg-white rounded-xl border border-beige-300/50 p-5 shadow-sm"
                >
                  <div className="flex items-start gap-4">
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-amber-100 flex items-center justify-center">
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#d97706" strokeWidth="2" strokeLinecap="round">
                        <path d="M12 3L21 19H3L12 3Z" />
                        <path d="M12 10V14" />
                      </svg>
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <Link
                          href={`/documents/view?id=${s.document.id}`}
                          className="text-sm font-medium text-[#1a1a1a] hover:text-accent truncate"
                        >
                          {s.document.title || s.document.filename}
                        </Link>
                        <TypeBadge type={s.document.doc_type} />
                      </div>
                      <p className="text-xs text-[#6b7280] mb-2">{s.reason}</p>
                      {s.suggested_procedure ? (
                        <Link
                          href={`/procedures/view?id=${s.suggested_procedure.id}`}
                          className="inline-flex items-center gap-1.5 text-xs font-medium text-accent hover:text-accent-hover transition-colors"
                        >
                          <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
                            <path d="M4 2H10C10.5 2 11 2.5 11 3V11C11 11.5 10.5 12 10 12H4C3.5 12 3 11.5 3 11V3C3 2.5 3.5 2 4 2Z" />
                            <path d="M5.5 5H8.5" />
                            <path d="M5.5 7H8.5" />
                            <path d="M5.5 9H7.5" />
                          </svg>
                          Procédure suggérée : {s.suggested_procedure.name}
                        </Link>
                      ) : (
                        <p className="text-xs text-[#9ca3af] italic">
                          Aucune procédure de renouvellement trouvée
                        </p>
                      )}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* Gaps tab */}
      {activeTab === 'gaps' && (
        <div className="space-y-4">
          {gaps.length === 0 ? (
            <div className="bg-white rounded-xl border border-beige-300/50 p-8 text-center">
              <svg width="48" height="48" viewBox="0 0 48 48" fill="none" stroke="#059669" strokeWidth="1.5" strokeLinecap="round" className="mx-auto mb-3">
                <circle cx="24" cy="24" r="16" />
                <path d="M16 24L22 30L32 18" />
              </svg>
              <p className="text-[#059669] font-medium">Pas de documents manquants détectés</p>
              <p className="text-sm text-[#6b7280] mt-1">
                L&apos;analyse compare les séries de documents récurrents (fiches de paie, factures, quittances) pour détecter les mois manquants.
              </p>
            </div>
          ) : (
            <div className="bg-white rounded-xl border border-beige-300/50 overflow-hidden">
              <div className="divide-y divide-beige-200">
                {gaps.map((gap, idx) => (
                  <div
                    key={idx}
                    className="flex items-center gap-4 px-5 py-4"
                  >
                    <div className="flex-shrink-0 w-10 h-10 rounded-lg bg-orange-100 flex items-center justify-center">
                      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="#ea580c" strokeWidth="2" strokeLinecap="round">
                        <path d="M6 4H14L18 8V20H6V4Z" />
                        <path d="M14 4V8H18" />
                        <path d="M10 13H14" />
                      </svg>
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-[#1a1a1a]">{gap.message}</p>
                      <p className="text-xs text-[#6b7280]">
                        Dernier document trouvé : {gap.last_seen_date || 'N/A'}
                        {gap.destinataire && ` · ${gap.destinataire}`}
                      </p>
                    </div>
                    <TypeBadge type={gap.doc_type} />
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
