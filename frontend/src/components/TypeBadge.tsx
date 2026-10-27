const TYPE_CONFIG: Record<string, { label: string; color: string; bg: string }> = {
  facture: { label: 'Facture', color: '#2E75B6', bg: '#dbeafe' },
  fiche_de_paie: { label: 'Bulletin de paie', color: '#059669', bg: '#d1fae5' },
  avis_imposition: { label: "Avis d'imposition", color: '#0891b2', bg: '#cffafe' },
  contrat: { label: 'Contrat', color: '#7c3aed', bg: '#ede9fe' },
  attestation: { label: 'Attestation', color: '#d97706', bg: '#fef3c7' },
  courrier: { label: 'Courrier', color: '#dc2626', bg: '#fee2e2' },
  banque: { label: 'Banque', color: '#be185d', bg: '#fce7f3' },
  quittance: { label: 'Quittance', color: '#4f46e5', bg: '#e0e7ff' },
  identite: { label: 'Identité', color: '#0d9488', bg: '#ccfbf1' },
  scolarite: { label: 'Scolarité', color: '#b45309', bg: '#ffedd5' },
  sante: { label: 'Santé', color: '#be123c', bg: '#ffe4e6' },
  logement: { label: 'Logement', color: '#4d7c0f', bg: '#ecfccb' },
  emploi: { label: 'Emploi', color: '#4338ca', bg: '#e0e7ff' },
  administratif: { label: 'Administratif', color: '#475569', bg: '#e2e8f0' },
  autre: { label: 'Autre', color: '#6b7280', bg: '#f3f4f6' },
};

const LEGACY_ALIASES: Record<string, string> = {
  releve_bancaire: 'banque',
  bulletin_de_paie: 'fiche_de_paie',
  bulletin_de_salaire: 'fiche_de_paie',
  rib: 'banque',
  cni: 'identite',
  passeport: 'identite',
};

function resolveType(type?: string): string {
  if (!type) return 'autre';
  return LEGACY_ALIASES[type] || type;
}

interface TypeBadgeProps {
  type?: string;
}

export default function TypeBadge({ type }: TypeBadgeProps) {
  const config = TYPE_CONFIG[resolveType(type)] || TYPE_CONFIG.autre;

  return (
    <span
      className="inline-flex items-center max-w-full px-2.5 py-0.5 rounded-full text-xs font-medium whitespace-nowrap"
      style={{ color: config.color, backgroundColor: config.bg }}
    >
      {config.label}
    </span>
  );
}

export function getTypeLabel(type?: string): string {
  return TYPE_CONFIG[resolveType(type)]?.label || TYPE_CONFIG.autre.label;
}

export function getTypeColor(type?: string): string {
  return TYPE_CONFIG[resolveType(type)]?.color || TYPE_CONFIG.autre.color;
}

export const DOC_TYPES = Object.entries(TYPE_CONFIG)
  .filter(([value]) => value !== 'autre')
  .map(([value, { label }]) => ({ value, label }))
  .concat([{ value: 'autre', label: TYPE_CONFIG.autre.label }]);
