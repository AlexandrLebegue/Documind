'use client';

import { useState, useEffect, Suspense } from 'react';
import { useSearchParams, useRouter } from 'next/navigation';
import { getProcedure, updateProcedure } from '@/lib/api';
import type { Procedure, ProcedureRequiredDocument } from '@/lib/api';
import { PROCEDURE_TYPES } from '@/components/ProcedureTypeBadge';
import { DOC_TYPES } from '@/components/TypeBadge';

interface EditableRequiredDoc {
  doc_type: string;
  label: string;
  description: string;
}

function ProcedureEditContent() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const procId = searchParams.get('id') || '';

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Form fields
  const [name, setName] = useState('');
  const [procedureType, setProcedureType] = useState('');
  const [description, setDescription] = useState('');
  const [remarks, setRemarks] = useState('');
  const [requiredDocs, setRequiredDocs] = useState<EditableRequiredDoc[]>([]);

  useEffect(() => {
    if (!procId) {
      setError('Aucun identifiant de procédure fourni');
      setLoading(false);
      return;
    }
    async function loadProcedure() {
      try {
        const proc = await getProcedure(procId);
        setName(proc.name);
        setProcedureType(proc.procedure_type);
        setDescription(proc.description || '');
        setRemarks(proc.remarks || '');
        setRequiredDocs(
          proc.required_documents.map((d) => ({
            doc_type: d.doc_type,
            label: d.label,
            description: d.description || '',
          })),
        );
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erreur de chargement');
      } finally {
        setLoading(false);
      }
    }
    loadProcedure();
  }, [procId]);

  const handleAddDoc = () => {
    setRequiredDocs((prev) => [...prev, { doc_type: 'autre', label: '', description: '' }]);
  };

  const handleRemoveDoc = (index: number) => {
    setRequiredDocs((prev) => prev.filter((_, i) => i !== index));
  };

  const handleDocChange = (index: number, field: keyof EditableRequiredDoc, value: string) => {
    setRequiredDocs((prev) =>
      prev.map((doc, i) => (i === index ? { ...doc, [field]: value } : doc)),
    );
  };

  const handleSave = async () => {
    if (!name.trim()) {
      setError('Le nom de la procédure est requis');
      return;
    }
    if (!procedureType) {
      setError('Le type de procédure est requis');
      return;
    }
    if (requiredDocs.some((d) => !d.label.trim())) {
      setError('Chaque document requis doit avoir un libellé');
      return;
    }

    setSaving(true);
    setError(null);

    try {
      const payload: {
        name: string;
        procedure_type: string;
        description?: string;
        remarks?: string;
        required_documents: ProcedureRequiredDocument[];
      } = {
        name: name.trim(),
        procedure_type: procedureType,
        required_documents: requiredDocs.map((d) => ({
          doc_type: d.doc_type,
          label: d.label.trim(),
          description: d.description.trim() || undefined,
        })),
      };

      if (description.trim()) {
        payload.description = description.trim();
      }
      if (remarks.trim()) {
        payload.remarks = remarks.trim();
      }

      await updateProcedure(procId, payload);
      router.push(`/procedures/view?id=${procId}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur lors de la sauvegarde');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="p-6 space-y-6 max-w-4xl">
        <div className="skeleton h-8 w-64 rounded-lg" />
        <div className="skeleton h-12 rounded-xl" />
        <div className="skeleton h-12 rounded-xl" />
        <div className="skeleton h-24 rounded-xl" />
        <div className="space-y-3">
          {[...Array(3)].map((_, i) => (
            <div key={i} className="skeleton h-16 rounded-xl" />
          ))}
        </div>
      </div>
    );
  }

  if (error && !name) {
    return (
      <div className="p-6">
        <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
          <p className="text-sm text-[#dc2626]">{error}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6 max-w-4xl">
      {/* Header */}
      <div className="flex items-center gap-3">
        <button
          onClick={() => router.push(`/procedures/view?id=${procId}`)}
          className="p-1.5 rounded-lg text-[#6b7280] hover:text-[#1a1a1a] hover:bg-beige-300/60 transition-colors"
        >
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M15 10H5" />
            <path d="M10 5L5 10L10 15" />
          </svg>
        </button>
        <div>
          <h1 className="text-2xl font-bold text-[#1a1a1a]">Modifier la procédure</h1>
          <p className="text-sm text-[#6b7280] mt-0.5">Modifiez les informations de votre procédure</p>
        </div>
      </div>

      {/* Error banner */}
      {error && (
        <div className="p-4 bg-red-50 border border-red-200 rounded-lg">
          <p className="text-sm text-[#dc2626]">{error}</p>
        </div>
      )}

      {/* Form */}
      <div className="space-y-5">
        {/* Name */}
        <div className="bg-white border border-beige-300/60 rounded-xl p-5 space-y-2">
          <label className="block text-sm font-medium text-[#1a1a1a]">
            Nom de la procédure <span className="text-[#dc2626]">*</span>
          </label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Ex: Inscription crèche, Ouverture compte..."
            className="w-full px-4 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent"
          />
        </div>

        {/* Type */}
        <div className="bg-white border border-beige-300/60 rounded-xl p-5 space-y-2">
          <label className="block text-sm font-medium text-[#1a1a1a]">
            Type de procédure <span className="text-[#dc2626]">*</span>
          </label>
          <select
            value={procedureType}
            onChange={(e) => setProcedureType(e.target.value)}
            className="w-full px-4 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent"
          >
            <option value="" disabled>
              Sélectionnez un type
            </option>
            {PROCEDURE_TYPES.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>
        </div>

        {/* Description */}
        <div className="bg-white border border-beige-300/60 rounded-xl p-5 space-y-2">
          <label className="block text-sm font-medium text-[#1a1a1a]">Description</label>
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Description de la procédure..."
            rows={3}
            className="w-full px-4 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent resize-none"
          />
        </div>

        {/* Remarks */}
        <div className="bg-white border border-beige-300/60 rounded-xl p-5 space-y-2">
          <label className="block text-sm font-medium text-[#1a1a1a]">Remarques</label>
          <textarea
            value={remarks}
            onChange={(e) => setRemarks(e.target.value)}
            placeholder="Remarques supplémentaires (optionnel)..."
            rows={2}
            className="w-full px-4 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent resize-none"
          />
        </div>

        {/* Required Documents */}
        <div className="bg-white border border-beige-300/60 rounded-xl p-5 space-y-4">
          <div className="flex items-center justify-between">
            <label className="block text-sm font-medium text-[#1a1a1a]">
              Documents requis ({requiredDocs.length})
            </label>
            <button
              onClick={handleAddDoc}
              className="flex items-center gap-1.5 px-3 py-1.5 bg-accent/10 text-accent rounded-lg text-xs font-medium hover:bg-accent/20 transition-colors"
            >
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <path d="M7 3V11" />
                <path d="M3 7H11" />
              </svg>
              Ajouter
            </button>
          </div>

          {requiredDocs.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-8 text-center">
              <p className="text-sm text-[#6b7280] mb-2">Aucun document requis</p>
              <button
                onClick={handleAddDoc}
                className="text-xs text-accent hover:text-accent-hover transition-colors font-medium"
              >
                + Ajouter un document
              </button>
            </div>
          ) : (
            <div className="space-y-3">
              {requiredDocs.map((doc, i) => (
                <div
                  key={i}
                  className="bg-beige-50 border border-beige-300/60 rounded-xl p-4 space-y-3"
                >
                  <div className="flex items-center justify-between">
                    <span className="flex items-center gap-2">
                      <span className="w-6 h-6 bg-accent/10 text-accent rounded-full flex items-center justify-center text-xs font-bold">
                        {i + 1}
                      </span>
                      <span className="text-xs font-medium text-[#6b7280]">Document requis</span>
                    </span>
                    <button
                      onClick={() => handleRemoveDoc(i)}
                      className="p-1 rounded-lg text-[#6b7280] hover:text-[#dc2626] hover:bg-red-50 transition-colors"
                      title="Supprimer ce document"
                    >
                      <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                        <path d="M3 3L11 11" />
                        <path d="M11 3L3 11" />
                      </svg>
                    </button>
                  </div>

                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                    {/* Doc type */}
                    <div>
                      <label className="block text-xs text-[#6b7280] mb-1">Type de document</label>
                      <select
                        value={doc.doc_type}
                        onChange={(e) => handleDocChange(i, 'doc_type', e.target.value)}
                        className="w-full px-3 py-2 bg-white border border-beige-300 rounded-lg text-sm text-[#1a1a1a] focus:outline-none focus:ring-2 focus:ring-accent/30"
                      >
                        {DOC_TYPES.map((t) => (
                          <option key={t.value} value={t.value}>
                            {t.label}
                          </option>
                        ))}
                      </select>
                    </div>

                    {/* Label */}
                    <div>
                      <label className="block text-xs text-[#6b7280] mb-1">
                        Libellé <span className="text-[#dc2626]">*</span>
                      </label>
                      <input
                        type="text"
                        value={doc.label}
                        onChange={(e) => handleDocChange(i, 'label', e.target.value)}
                        placeholder="Ex: Justificatif de domicile"
                        className="w-full px-3 py-2 bg-white border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30"
                      />
                    </div>
                  </div>

                  {/* Description */}
                  <div>
                    <label className="block text-xs text-[#6b7280] mb-1">Description</label>
                    <input
                      type="text"
                      value={doc.description}
                      onChange={(e) => handleDocChange(i, 'description', e.target.value)}
                      placeholder="Détails supplémentaires sur ce document..."
                      className="w-full px-3 py-2 bg-white border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#6b7280] focus:outline-none focus:ring-2 focus:ring-accent/30"
                    />
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Action buttons */}
      <div className="flex items-center justify-end gap-3 pt-2 pb-8">
        <button
          onClick={() => router.push(`/procedures/view?id=${procId}`)}
          className="px-5 py-2.5 bg-white border border-beige-300 text-[#1a1a1a] rounded-lg text-sm font-medium hover:bg-beige-50 transition-colors"
          disabled={saving}
        >
          Annuler
        </button>
        <button
          onClick={handleSave}
          disabled={saving}
          className="flex items-center gap-2 px-5 py-2.5 bg-accent hover:bg-accent-hover text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {saving ? (
            <>
              <svg className="animate-spin h-4 w-4" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
              </svg>
              Enregistrement...
            </>
          ) : (
            <>
              <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M3 8L6.5 11.5L13 5" />
              </svg>
              Enregistrer
            </>
          )}
        </button>
      </div>
    </div>
  );
}

export default function ProcedureEditPage() {
  return (
    <Suspense
      fallback={
        <div className="p-6 space-y-6 max-w-4xl">
          <div className="skeleton h-8 w-64 rounded-lg" />
          <div className="skeleton h-12 rounded-xl" />
          <div className="skeleton h-12 rounded-xl" />
          <div className="skeleton h-24 rounded-xl" />
          <div className="space-y-3">
            {[...Array(3)].map((_, i) => (
              <div key={i} className="skeleton h-16 rounded-xl" />
            ))}
          </div>
        </div>
      }
    >
      <ProcedureEditContent />
    </Suspense>
  );
}
