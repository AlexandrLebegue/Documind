const TYPE_COLORS: Record<string, string> = {
  facture: '#2E75B6',
  fiche_de_paie: '#059669',
  contrat: '#7c3aed',
  attestation: '#d97706',
  courrier: '#dc2626',
  avis_imposition: '#0891b2',
  releve_bancaire: '#be185d',
  quittance: '#4f46e5',
  autre: '#6b7280',
};

const TYPE_LABELS: Record<string, string> = {
  facture: 'Facture',
  fiche_de_paie: 'Fiche de paie',
  contrat: 'Contrat',
  attestation: 'Attestation',
  courrier: 'Courrier',
  avis_imposition: 'Avis d\'imposition',
  releve_bancaire: 'Relevé bancaire',
  quittance: 'Quittance',
  autre: 'Autre',
};

interface PieChartProps {
  data: Record<string, number>;
}

export default function PieChart({ data }: PieChartProps) {
  const entries = Object.entries(data).filter(([, count]) => count > 0);
  const total = entries.reduce((sum, [, count]) => sum + count, 0);

  if (total === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-8 text-[#6b7280]">
        <svg width="48" height="48" viewBox="0 0 48 48" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
          <circle cx="24" cy="24" r="18" strokeDasharray="4 4" />
          <path d="M24 14V24L32 28" />
        </svg>
        <p className="text-sm mt-2">Aucune donnée</p>
      </div>
    );
  }

  // Generate pie slices
  const size = 160;
  const center = size / 2;
  const radius = 60;
  let currentAngle = -Math.PI / 2; // Start from top

  const slices = entries.map(([type, count]) => {
    const angle = (count / total) * 2 * Math.PI;
    const startAngle = currentAngle;
    const endAngle = currentAngle + angle;
    currentAngle = endAngle;

    const x1 = center + radius * Math.cos(startAngle);
    const y1 = center + radius * Math.sin(startAngle);
    const x2 = center + radius * Math.cos(endAngle);
    const y2 = center + radius * Math.sin(endAngle);

    const largeArc = angle > Math.PI ? 1 : 0;

    // For single-entry case, draw a circle
    if (entries.length === 1) {
      return {
        type,
        count,
        path: `M ${center} ${center - radius} A ${radius} ${radius} 0 1 1 ${center - 0.001} ${center - radius} Z`,
        color: TYPE_COLORS[type] || TYPE_COLORS.autre,
      };
    }

    const path = `M ${center} ${center} L ${x1} ${y1} A ${radius} ${radius} 0 ${largeArc} 1 ${x2} ${y2} Z`;

    return {
      type,
      count,
      path,
      color: TYPE_COLORS[type] || TYPE_COLORS.autre,
    };
  });

  return (
    <div className="flex flex-col items-center">
      {/* SVG Pie */}
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} className="mb-4">
        {slices.map((slice, idx) => (
          <path
            key={idx}
            d={slice.path}
            fill={slice.color}
            stroke="white"
            strokeWidth="2"
          />
        ))}
        {/* Center circle for donut effect */}
        <circle cx={center} cy={center} r="35" fill="white" />
        <text x={center} y={center - 4} textAnchor="middle" className="text-lg font-bold" fill="#1a1a1a" fontSize="18">
          {total}
        </text>
        <text x={center} y={center + 12} textAnchor="middle" fill="#6b7280" fontSize="10">
          documents
        </text>
      </svg>

      {/* Legend */}
      <div className="w-full space-y-1.5">
        {slices.map((slice, idx) => (
          <div key={idx} className="flex items-center justify-between text-xs">
            <div className="flex items-center gap-2">
              <span
                className="w-2.5 h-2.5 rounded-full flex-shrink-0"
                style={{ backgroundColor: slice.color }}
              />
              <span className="text-[#1a1a1a]">
                {TYPE_LABELS[slice.type] || slice.type}
              </span>
            </div>
            <span className="text-[#6b7280] font-medium">{slice.count}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
