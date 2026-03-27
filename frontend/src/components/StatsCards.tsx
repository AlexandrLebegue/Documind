import Link from 'next/link';
import type { Stats, Health } from '@/lib/api';

interface StatsCardsProps {
  stats: Stats | null;
  health: Health | null;
}

export default function StatsCards({ stats, health }: StatsCardsProps) {
  const currentMonth = new Date().toISOString().slice(0, 7); // YYYY-MM
  const docsThisMonth = stats?.count_by_month?.[currentMonth] || 0;

  const alertCount = (stats?.expiring_soon_count || 0) + (stats?.overdue_count || 0);
  const hasAlerts = alertCount > 0;

  const cards = [
    {
      label: 'Total documents',
      value: stats?.total_documents?.toString() || '0',
      icon: (
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#2E75B6" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <path d="M6 4H14L18 8V20H6V4Z" />
          <path d="M14 4V8H18" />
          <path d="M8 12H16" />
          <path d="M8 16H13" />
        </svg>
      ),
      bgColor: '#dbeafe',
      href: '/documents',
    },
    {
      label: 'Ce mois-ci',
      value: docsThisMonth.toString(),
      icon: (
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#059669" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <rect x="4" y="5" width="16" height="16" rx="2" />
          <path d="M4 10H20" />
          <path d="M8 3V6" />
          <path d="M16 3V6" />
        </svg>
      ),
      bgColor: '#d1fae5',
      href: undefined,
    },
    {
      label: 'Alertes',
      value: alertCount > 0 ? alertCount.toString() : 'Aucune',
      icon: hasAlerts ? (
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#d97706" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <path d="M12 3L21 19H3L12 3Z" />
          <path d="M12 10V14" />
          <circle cx="12" cy="17" r="0.5" fill="#d97706" />
        </svg>
      ) : (
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#059669" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="12" cy="12" r="9" />
          <path d="M8 12L11 15L16 9" />
        </svg>
      ),
      bgColor: hasAlerts ? '#fef3c7' : '#d1fae5',
      href: '/alerts',
    },
    {
      label: 'Système',
      value: health?.llm_loaded ? 'Opérationnel' : 'Hors ligne',
      icon: health?.llm_loaded ? (
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
          <circle cx="12" cy="12" r="6" fill="#059669" opacity="0.2" />
          <circle cx="12" cy="12" r="4" fill="#059669" />
        </svg>
      ) : (
        <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
          <circle cx="12" cy="12" r="6" fill="#dc2626" opacity="0.2" />
          <circle cx="12" cy="12" r="4" fill="#dc2626" />
        </svg>
      ),
      bgColor: health?.llm_loaded ? '#d1fae5' : '#fee2e2',
      href: '/settings',
    },
  ];

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
      {cards.map((card, idx) => {
        const inner = (
          <div className={`bg-white rounded-xl border border-beige-300/50 p-4 shadow-sm ${card.href ? 'hover:shadow-md hover:border-beige-300 transition-all cursor-pointer' : ''}`}>
            <div className="flex items-center gap-3">
              <div
                className="w-10 h-10 rounded-lg flex items-center justify-center"
                style={{ backgroundColor: card.bgColor }}
              >
                {card.icon}
              </div>
              <div>
                <p className="text-xs text-[#6b7280] font-medium">{card.label}</p>
                <p className="text-lg font-bold text-[#1a1a1a]">{card.value}</p>
              </div>
            </div>
          </div>
        );

        return card.href ? (
          <Link key={idx} href={card.href}>{inner}</Link>
        ) : (
          <div key={idx}>{inner}</div>
        );
      })}
    </div>
  );
}
