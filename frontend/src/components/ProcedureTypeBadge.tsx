const PROCEDURE_TYPE_CONFIG: Record<string, { label: string; color: string; bg: string }> = {
  administrative: { label: 'Administrative', color: '#2E75B6', bg: '#dbeafe' },
  contrat: { label: 'Contrat', color: '#7c3aed', bg: '#ede9fe' },
  bancaire: { label: 'Bancaire', color: '#059669', bg: '#d1fae5' },
  sante: { label: 'Santé', color: '#dc2626', bg: '#fee2e2' },
  emploi: { label: 'Emploi', color: '#d97706', bg: '#fef3c7' },
  immobilier: { label: 'Immobilier', color: '#0891b2', bg: '#cffafe' },
};

interface ProcedureTypeBadgeProps {
  type?: string;
}

export default function ProcedureTypeBadge({ type }: ProcedureTypeBadgeProps) {
  const config = PROCEDURE_TYPE_CONFIG[type || ''] || { label: type || 'Autre', color: '#6b7280', bg: '#f3f4f6' };

  return (
    <span
      className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
      style={{ color: config.color, backgroundColor: config.bg }}
    >
      {config.label}
    </span>
  );
}

export function getProcedureTypeLabel(type?: string): string {
  return PROCEDURE_TYPE_CONFIG[type || '']?.label || type || 'Autre';
}

export const PROCEDURE_TYPES = Object.entries(PROCEDURE_TYPE_CONFIG).map(([value, { label }]) => ({ value, label }));
