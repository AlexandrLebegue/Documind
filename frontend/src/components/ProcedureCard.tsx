import Link from 'next/link';
import type { Procedure } from '@/lib/api';
import ProcedureTypeBadge from './ProcedureTypeBadge';

interface ProcedureCardProps {
  procedure: Procedure;
}

export default function ProcedureCard({ procedure }: ProcedureCardProps) {
  const docCount = procedure.required_documents?.length || 0;
  const createdDate = new Date(procedure.created_at).toLocaleDateString('fr-FR', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
  });

  return (
    <Link
      href={`/procedures/view?id=${procedure.id}`}
      className="block bg-white border border-beige-300/60 rounded-xl p-5 hover:shadow-md hover:border-accent/30 transition-all group"
    >
      <div className="flex items-start justify-between mb-3">
        <ProcedureTypeBadge type={procedure.procedure_type} />
        <span className="text-xs text-[#6b7280]">{createdDate}</span>
      </div>

      <h3 className="text-sm font-semibold text-[#1a1a1a] mb-1.5 group-hover:text-accent transition-colors line-clamp-2">
        {procedure.name}
      </h3>

      {procedure.description && (
        <p className="text-xs text-[#6b7280] mb-3 line-clamp-2">
          {procedure.description}
        </p>
      )}

      <div className="flex items-center gap-2 text-xs text-[#6b7280]">
        <svg width="14" height="14" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <path d="M5 3H12L15 6V17H5V3Z" />
          <path d="M12 3V6H15" />
        </svg>
        <span>{docCount} document{docCount !== 1 ? 's' : ''} requis</span>
      </div>
    </Link>
  );
}
