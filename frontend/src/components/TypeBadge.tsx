const TYPE_CONFIG: Record<string, { label: string; color: string; bg: string }> = {
  facture: { label: 'Facture', color: '#2E75B6', bg: '#dbeafe' },
  fiche_de_paie: { label: 'Fiche de paie', color: '#059669', bg: '#d1fae5' },
  contrat: { label: 'Contrat', color: '#7c3aed', bg: '#ede9fe' },
  attestation: { label: 'Attestation', color: '#d97706', bg: '#fef3c7' },
  courrier: { label: 'Courrier', color: '#dc2626', bg: '#fee2e2' },
  avis_imposition: { label: 'Avis d\'imposition', color: '#0891b2', bg: '#cffafe' },
  releve_bancaire: { label: 'Relevé bancaire', color: '#be185d', bg: '#fce7f3' },
  quittance: { label: 'Quittance', color: '#4f46e5', bg: '#e0e7ff' },
  identite: { label: 'Identité', color: '#0d9488', bg: '#ccfbf1' },
  autre: { label: 'Autre', color: '#6b7280', bg: '#f3f4f6' },
};

interface TypeBadgeProps {
  type?: string;
}

export default function TypeBadge({ type }: TypeBadgeProps) {
  const config = TYPE_CONFIG[type || ''] || TYPE_CONFIG.autre;

  return (
    <span
      className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium"
      style={{ color: config.color, backgroundColor: config.bg }}
    >
      {config.label}
    </span>
  );
}

export function getTypeLabel(type?: string): string {
  return TYPE_CONFIG[type || '']?.label || TYPE_CONFIG.autre.label;
}

export function getTypeColor(type?: string): string {
  return TYPE_CONFIG[type || '']?.color || TYPE_CONFIG.autre.color;
}

export const DOC_TYPES = Object.entries(TYPE_CONFIG).map(([value, { label }]) => ({ value, label }));
