'use client';

import { useState } from 'react';
import type { Document } from '@/lib/api';
import { DOC_TYPES } from './TypeBadge';

interface MetadataEditorProps {
  document: Document;
  onSave: (updates: Partial<Document>) => void;
}

interface FieldConfig {
  key: keyof Document;
  label: string;
  type: 'text' | 'select' | 'date' | 'number' | 'textarea';
  options?: { value: string; label: string }[];
}

const fields: FieldConfig[] = [
  { key: 'title', label: 'Titre', type: 'text' },
  { key: 'doc_type', label: 'Type', type: 'select', options: DOC_TYPES },
  { key: 'emetteur', label: 'Émetteur', type: 'text' },
  { key: 'doc_date', label: 'Date', type: 'date' },
  { key: 'montant', label: 'Montant (€)', type: 'number' },
  { key: 'reference', label: 'Référence', type: 'text' },
  { key: 'destinataire', label: 'Destinataire', type: 'text' },
  { key: 'date_expiration', label: 'Date d\'expiration', type: 'date' },
  { key: 'date_echeance', label: 'Date d\'échéance', type: 'date' },
  { key: 'resume', label: 'Résumé', type: 'textarea' },
];

export default function MetadataEditor({ document, onSave }: MetadataEditorProps) {
  const [editingField, setEditingField] = useState<string | null>(null);
  const [editValues, setEditValues] = useState<Record<string, string>>({});
  const [tags, setTags] = useState<string[]>(document.tags || []);
  const [newTag, setNewTag] = useState('');
  const [saving, setSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);

  const startEdit = (fieldKey: string) => {
    const currentValue = document[fieldKey as keyof Document];
    setEditValues((prev) => ({
      ...prev,
      [fieldKey]: currentValue != null ? String(currentValue) : '',
    }));
    setEditingField(fieldKey);
  };

  const cancelEdit = () => {
    setEditingField(null);
  };

  const confirmEdit = (fieldKey: string) => {
    setEditingField(null);
    setHasChanges(true);
  };

  const handleKeyDown = (e: React.KeyboardEvent, fieldKey: string) => {
    if (e.key === 'Enter' && fieldKey !== 'resume') {
      confirmEdit(fieldKey);
    }
    if (e.key === 'Escape') {
      cancelEdit();
    }
  };

  const addTag = () => {
    const trimmed = newTag.trim();
    if (trimmed && !tags.includes(trimmed)) {
      setTags([...tags, trimmed]);
      setNewTag('');
      setHasChanges(true);
    }
  };

  const removeTag = (tag: string) => {
    setTags(tags.filter((t) => t !== tag));
    setHasChanges(true);
  };

  const handleSave = async () => {
    setSaving(true);
    const updates: Partial<Document> = {};

    for (const field of fields) {
      if (editValues[field.key] !== undefined) {
        const val = editValues[field.key];
        if (field.type === 'number') {
          (updates as Record<string, unknown>)[field.key] = val ? parseFloat(val) : null;
        } else {
          (updates as Record<string, unknown>)[field.key] = val || null;
        }
      }
    }

    updates.tags = tags;

    try {
      await onSave(updates);
      setHasChanges(false);
    } finally {
      setSaving(false);
    }
  };

  const getDisplayValue = (field: FieldConfig): string => {
    // Check if we have an edited value
    if (editValues[field.key] !== undefined) {
      const val = editValues[field.key];
      if (field.type === 'select' && field.options) {
        return field.options.find((o) => o.value === val)?.label || val || '-';
      }
      if (field.type === 'date' && val) {
        return new Date(val).toLocaleDateString('fr-FR');
      }
      if (field.type === 'number' && val) {
        return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(parseFloat(val));
      }
      return val || '-';
    }

    // Otherwise use original document value
    const rawValue = document[field.key as keyof Document];
    if (rawValue == null) return '-';

    if (field.type === 'select' && field.options) {
      return field.options.find((o) => o.value === String(rawValue))?.label || String(rawValue);
    }
    if (field.type === 'date') {
      return new Date(String(rawValue)).toLocaleDateString('fr-FR');
    }
    if (field.type === 'number') {
      return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(Number(rawValue));
    }
    return String(rawValue);
  };

  return (
    <div className="space-y-4">
      {fields.map((field) => (
        <div key={field.key} className="group">
          <label className="block text-xs font-medium text-[#6b7280] mb-1">{field.label}</label>

          {editingField === field.key ? (
            <div className="flex gap-2">
              {field.type === 'select' ? (
                <select
                  value={editValues[field.key] || ''}
                  onChange={(e) => setEditValues((prev) => ({ ...prev, [field.key]: e.target.value }))}
                  onBlur={() => confirmEdit(field.key)}
                  autoFocus
                  className="flex-1 px-3 py-1.5 text-sm border border-accent rounded-lg focus:outline-none focus:ring-2 focus:ring-accent/30 bg-white"
                >
                  <option value="">—</option>
                  {field.options?.map((opt) => (
                    <option key={opt.value} value={opt.value}>
                      {opt.label}
                    </option>
                  ))}
                </select>
              ) : field.type === 'textarea' ? (
                <textarea
                  value={editValues[field.key] || ''}
                  onChange={(e) => setEditValues((prev) => ({ ...prev, [field.key]: e.target.value }))}
                  onBlur={() => confirmEdit(field.key)}
                  onKeyDown={(e) => {
                    if (e.key === 'Escape') cancelEdit();
                  }}
                  autoFocus
                  rows={3}
                  className="flex-1 px-3 py-1.5 text-sm border border-accent rounded-lg focus:outline-none focus:ring-2 focus:ring-accent/30 bg-white resize-none"
                />
              ) : (
                <input
                  type={field.type === 'number' ? 'number' : field.type === 'date' ? 'date' : 'text'}
                  value={editValues[field.key] || ''}
                  onChange={(e) => setEditValues((prev) => ({ ...prev, [field.key]: e.target.value }))}
                  onBlur={() => confirmEdit(field.key)}
                  onKeyDown={(e) => handleKeyDown(e, field.key)}
                  autoFocus
                  step={field.type === 'number' ? '0.01' : undefined}
                  className="flex-1 px-3 py-1.5 text-sm border border-accent rounded-lg focus:outline-none focus:ring-2 focus:ring-accent/30 bg-white"
                />
              )}
            </div>
          ) : (
            <div
              onClick={() => startEdit(field.key)}
              className="px-3 py-1.5 text-sm text-[#1a1a1a] bg-beige-50 rounded-lg border border-transparent hover:border-beige-300 cursor-pointer group-hover:bg-beige-100 transition-colors min-h-[34px] flex items-center"
            >
              {getDisplayValue(field)}
              <svg
                width="14"
                height="14"
                viewBox="0 0 14 14"
                fill="none"
                stroke="#6b7280"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
                className="ml-auto opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0"
              >
                <path d="M8.5 2.5L11.5 5.5" />
                <path d="M2 10L1.5 12.5L4 12L11 5L9 3L2 10Z" />
              </svg>
            </div>
          )}
        </div>
      ))}

      {/* Tags */}
      <div>
        <label className="block text-xs font-medium text-[#6b7280] mb-1">Tags</label>
        <div className="flex flex-wrap gap-1.5 mb-2">
          {tags.map((tag) => (
            <span
              key={tag}
              className="inline-flex items-center gap-1 px-2.5 py-0.5 bg-accent-light text-accent text-xs font-medium rounded-full"
            >
              {tag}
              <button
                onClick={() => removeTag(tag)}
                className="hover:text-accent-hover"
              >
                <svg width="12" height="12" viewBox="0 0 12 12" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
                  <path d="M3 3L9 9" />
                  <path d="M9 3L3 9" />
                </svg>
              </button>
            </span>
          ))}
        </div>
        <div className="flex gap-2">
          <input
            type="text"
            value={newTag}
            onChange={(e) => setNewTag(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') {
                e.preventDefault();
                addTag();
              }
            }}
            placeholder="Ajouter un tag..."
            className="flex-1 px-3 py-1.5 text-sm border border-beige-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-accent/30 bg-white"
          />
          <button
            onClick={addTag}
            disabled={!newTag.trim()}
            className="px-3 py-1.5 text-sm bg-beige-100 hover:bg-beige-200 rounded-lg border border-beige-300 disabled:opacity-50"
          >
            +
          </button>
        </div>
      </div>

      {/* Save Button */}
      {hasChanges && (
        <button
          onClick={handleSave}
          disabled={saving}
          className="w-full px-4 py-2 bg-accent hover:bg-accent-hover text-white text-sm font-medium rounded-lg disabled:opacity-50 transition-colors"
        >
          {saving ? 'Enregistrement...' : 'Enregistrer les modifications'}
        </button>
      )}
    </div>
  );
}
