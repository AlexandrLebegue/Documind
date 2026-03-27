'use client';

interface AlertBadgeProps {
  urgency: 'critical' | 'warning' | 'info';
  label?: string;
  size?: 'sm' | 'md';
}

const urgencyConfig = {
  critical: {
    bg: 'bg-red-100',
    text: 'text-red-700',
    border: 'border-red-200',
    dot: 'bg-red-500',
    defaultLabel: 'Urgent',
  },
  warning: {
    bg: 'bg-amber-100',
    text: 'text-amber-700',
    border: 'border-amber-200',
    dot: 'bg-amber-500',
    defaultLabel: 'Bientôt',
  },
  info: {
    bg: 'bg-blue-100',
    text: 'text-blue-700',
    border: 'border-blue-200',
    dot: 'bg-blue-500',
    defaultLabel: 'À surveiller',
  },
};

export default function AlertBadge({ urgency, label, size = 'sm' }: AlertBadgeProps) {
  const config = urgencyConfig[urgency] || urgencyConfig.info;
  const displayLabel = label || config.defaultLabel;

  const sizeClasses = size === 'sm'
    ? 'px-2 py-0.5 text-[10px]'
    : 'px-2.5 py-1 text-xs';

  return (
    <span
      className={`inline-flex items-center gap-1 ${sizeClasses} font-medium rounded-full border ${config.bg} ${config.text} ${config.border}`}
    >
      <span className={`w-1.5 h-1.5 rounded-full ${config.dot}`} />
      {displayLabel}
    </span>
  );
}

export function ExpiryBadge({ dateExpiration }: { dateExpiration: string }) {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const expDate = new Date(dateExpiration);
  expDate.setHours(0, 0, 0, 0);

  const diffMs = expDate.getTime() - today.getTime();
  const daysRemaining = Math.ceil(diffMs / (1000 * 60 * 60 * 24));

  if (daysRemaining < 0) {
    return <AlertBadge urgency="critical" label="Expiré" />;
  }
  if (daysRemaining <= 7) {
    return <AlertBadge urgency="critical" label={`Expire dans ${daysRemaining}j`} />;
  }
  if (daysRemaining <= 30) {
    return <AlertBadge urgency="warning" label={`Expire dans ${daysRemaining}j`} />;
  }
  return null;
}

export function EcheanceBadge({ dateEcheance }: { dateEcheance: string }) {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const echDate = new Date(dateEcheance);
  echDate.setHours(0, 0, 0, 0);

  const diffMs = echDate.getTime() - today.getTime();
  const daysRemaining = Math.ceil(diffMs / (1000 * 60 * 60 * 24));

  if (daysRemaining < 0) {
    return <AlertBadge urgency="critical" label="En retard" />;
  }
  if (daysRemaining <= 7) {
    return <AlertBadge urgency="critical" label={`Échéance ${daysRemaining}j`} />;
  }
  if (daysRemaining <= 30) {
    return <AlertBadge urgency="warning" label={`Échéance ${daysRemaining}j`} />;
  }
  return null;
}
