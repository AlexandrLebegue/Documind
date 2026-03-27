interface StatusBadgeProps {
  status: string;
}

export default function StatusBadge({ status }: StatusBadgeProps) {
  const config = getStatusConfig(status);

  return (
    <span className="inline-flex items-center gap-1.5 text-xs font-medium">
      <span
        className={`w-2 h-2 rounded-full ${config.dotClass}`}
        style={{ backgroundColor: config.color }}
      />
      <span style={{ color: config.color }}>{config.label}</span>
    </span>
  );
}

function getStatusConfig(status: string) {
  switch (status) {
    case 'processing':
      return { label: 'En cours...', color: '#d97706', dotClass: 'pulse-dot' };
    case 'ready':
      return { label: 'Prêt', color: '#059669', dotClass: '' };
    case 'error':
      return { label: 'Erreur', color: '#dc2626', dotClass: '' };
    default:
      return { label: status, color: '#6b7280', dotClass: '' };
  }
}
