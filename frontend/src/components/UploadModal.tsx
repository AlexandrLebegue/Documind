'use client';

import { useState, useRef, useCallback } from 'react';
import { uploadDocument } from '@/lib/api';

interface UploadModalProps {
  isOpen: boolean;
  onClose: () => void;
  onUploadComplete: () => void;
}

interface FileEntry {
  file: File;
  status: 'pending' | 'uploading' | 'done' | 'error';
  error?: string;
}

const ACCEPTED_FORMATS = ['.pdf', '.jpg', '.jpeg', '.png', '.tiff', '.webp'];
const MAX_SIZE = 50 * 1024 * 1024; // 50MB

export default function UploadModal({ isOpen, onClose, onUploadComplete }: UploadModalProps) {
  const [files, setFiles] = useState<FileEntry[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const [uploading, setUploading] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const validateFile = (file: File): string | null => {
    const ext = '.' + file.name.split('.').pop()?.toLowerCase();
    if (!ACCEPTED_FORMATS.includes(ext)) {
      return `Format non supporté: ${ext}`;
    }
    if (file.size > MAX_SIZE) {
      return `Fichier trop volumineux (max 50 Mo)`;
    }
    return null;
  };

  const addFiles = useCallback((newFiles: FileList | File[]) => {
    const entries: FileEntry[] = Array.from(newFiles).map((file) => {
      const error = validateFile(file);
      return { file, status: error ? 'error' : 'pending', error: error || undefined } as FileEntry;
    });
    setFiles((prev) => [...prev, ...entries]);
  }, []);

  const removeFile = (index: number) => {
    setFiles((prev) => prev.filter((_, i) => i !== index));
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  };

  const handleDragLeave = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    if (e.dataTransfer.files.length > 0) {
      addFiles(e.dataTransfer.files);
    }
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files.length > 0) {
      addFiles(e.target.files);
      // Reset input so the same files can be re-selected
      e.target.value = '';
    }
  };

  const handleUpload = async () => {
    setUploading(true);
    const updatedFiles = [...files];

    for (let i = 0; i < updatedFiles.length; i++) {
      if (updatedFiles[i].status !== 'pending') continue;

      updatedFiles[i] = { ...updatedFiles[i], status: 'uploading' };
      setFiles([...updatedFiles]);

      try {
        await uploadDocument(updatedFiles[i].file);
        updatedFiles[i] = { ...updatedFiles[i], status: 'done' };
      } catch (err) {
        updatedFiles[i] = {
          ...updatedFiles[i],
          status: 'error',
          error: err instanceof Error ? err.message : 'Erreur inconnue',
        };
      }
      setFiles([...updatedFiles]);
    }

    setUploading(false);

    // Check if all files are done
    const allDone = updatedFiles.every((f) => f.status === 'done' || f.status === 'error');
    const anyDone = updatedFiles.some((f) => f.status === 'done');
    if (allDone && anyDone) {
      onUploadComplete();
    }
  };

  const handleClose = () => {
    if (!uploading) {
      setFiles([]);
      onClose();
    }
  };

  const formatSize = (bytes: number) => {
    if (bytes < 1024) return `${bytes} o`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} Ko`;
    return `${(bytes / (1024 * 1024)).toFixed(1)} Mo`;
  };

  const pendingCount = files.filter((f) => f.status === 'pending').length;

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={handleClose}>
      <div
        className="bg-white rounded-xl shadow-xl w-full max-w-lg mx-4 max-h-[80vh] flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-beige-300">
          <h2 className="text-lg font-semibold text-[#1a1a1a]">Ajouter des documents</h2>
          <button
            onClick={handleClose}
            disabled={uploading}
            className="p-1 rounded hover:bg-beige-100 text-[#6b7280] disabled:opacity-50"
          >
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
              <path d="M5 5L15 15" />
              <path d="M15 5L5 15" />
            </svg>
          </button>
        </div>

        {/* Drop Zone */}
        <div className="px-6 pt-4">
          <div
            onDragOver={handleDragOver}
            onDragLeave={handleDragLeave}
            onDrop={handleDrop}
            onClick={() => inputRef.current?.click()}
            className={`border-2 border-dashed rounded-xl p-8 text-center cursor-pointer transition-colors ${
              isDragging
                ? 'border-accent bg-accent-light/30'
                : 'border-beige-300 hover:border-accent/50 hover:bg-beige-50'
            }`}
          >
            <div className="flex justify-center mb-3">
              <svg width="40" height="40" viewBox="0 0 40 40" fill="none" stroke="#6b7280" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M8 6H24L30 12V34H8V6Z" />
                <path d="M24 6V12H30" />
                <path d="M20 20V28" />
                <path d="M16 24L20 20L24 24" />
              </svg>
            </div>
            <p className="text-sm text-[#6b7280]">
              Glissez vos fichiers ici ou <span className="text-accent font-medium">cliquez pour sélectionner</span>
            </p>
            <p className="text-xs text-[#6b7280] mt-1">
              PDF, JPG, PNG, TIFF, WebP — max 50 Mo par fichier
            </p>
            <input
              ref={inputRef}
              type="file"
              multiple
              accept={ACCEPTED_FORMATS.join(',')}
              onChange={handleInputChange}
              className="hidden"
            />
          </div>
        </div>

        {/* File List */}
        {files.length > 0 && (
          <div className="flex-1 overflow-auto px-6 py-3 space-y-2">
            {files.map((entry, idx) => (
              <div
                key={idx}
                className="flex items-center gap-3 p-2.5 rounded-lg bg-beige-50 border border-beige-300/50"
              >
                {/* Status icon */}
                <div className="flex-shrink-0">
                  {entry.status === 'pending' && (
                    <div className="w-5 h-5 rounded-full border-2 border-beige-300" />
                  )}
                  {entry.status === 'uploading' && (
                    <div className="w-5 h-5 rounded-full border-2 border-accent border-t-transparent animate-spin" />
                  )}
                  {entry.status === 'done' && (
                    <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
                      <circle cx="10" cy="10" r="8" fill="#059669" />
                      <path d="M7 10L9 12L13 8" stroke="white" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
                    </svg>
                  )}
                  {entry.status === 'error' && (
                    <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
                      <circle cx="10" cy="10" r="8" fill="#dc2626" />
                      <path d="M7.5 7.5L12.5 12.5" stroke="white" strokeWidth="1.5" strokeLinecap="round" />
                      <path d="M12.5 7.5L7.5 12.5" stroke="white" strokeWidth="1.5" strokeLinecap="round" />
                    </svg>
                  )}
                </div>

                {/* File info */}
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-medium text-[#1a1a1a] truncate">{entry.file.name}</p>
                  <p className="text-xs text-[#6b7280]">
                    {formatSize(entry.file.size)}
                    {entry.error && <span className="text-[#dc2626] ml-2">{entry.error}</span>}
                  </p>
                </div>

                {/* Remove button */}
                {!uploading && (
                  <button
                    onClick={() => removeFile(idx)}
                    className="flex-shrink-0 p-1 rounded hover:bg-beige-200 text-[#6b7280]"
                  >
                    <svg width="14" height="14" viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
                      <path d="M3 3L11 11" />
                      <path d="M11 3L3 11" />
                    </svg>
                  </button>
                )}
              </div>
            ))}
          </div>
        )}

        {/* Footer */}
        <div className="px-6 py-4 border-t border-beige-300 flex items-center justify-between">
          <p className="text-sm text-[#6b7280]">
            {files.length > 0 ? `${files.length} fichier(s) sélectionné(s)` : 'Aucun fichier sélectionné'}
          </p>
          <div className="flex gap-2">
            <button
              onClick={handleClose}
              disabled={uploading}
              className="px-4 py-2 text-sm rounded-lg border border-beige-300 text-[#1a1a1a] hover:bg-beige-100 disabled:opacity-50"
            >
              Annuler
            </button>
            <button
              onClick={handleUpload}
              disabled={uploading || pendingCount === 0}
              className="px-4 py-2 text-sm rounded-lg bg-accent hover:bg-accent-hover text-white font-medium disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {uploading ? 'Envoi en cours...' : `Envoyer (${pendingCount})`}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
