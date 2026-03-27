'use client';

import { useState, useEffect } from 'react';
import { getSettings, updateSettings } from '@/lib/api';
import type { Settings } from '@/lib/api';

export default function SettingsPage() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  // Form state
  const [apiKey, setApiKey] = useState('');
  const [model, setModel] = useState('');
  const [baseUrl, setBaseUrl] = useState('');
  const [showApiKey, setShowApiKey] = useState(false);
  const [apiKeyChanged, setApiKeyChanged] = useState(false);

  useEffect(() => {
    async function fetchSettings() {
      try {
        const data = await getSettings();
        setSettings(data);
        setApiKey(data.openrouter_api_key);
        setModel(data.openrouter_model);
        setBaseUrl(data.openrouter_base_url);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erreur de chargement');
      } finally {
        setLoading(false);
      }
    }
    fetchSettings();
  }, []);

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    setSuccess(false);

    try {
      const payload: Record<string, string> = {};

      // Only send API key if it was actually changed (not the masked value)
      if (apiKeyChanged && apiKey) {
        payload.openrouter_api_key = apiKey;
      }
      if (model !== settings?.openrouter_model) {
        payload.openrouter_model = model;
      }
      if (baseUrl !== settings?.openrouter_base_url) {
        payload.openrouter_base_url = baseUrl;
      }

      if (Object.keys(payload).length === 0) {
        setSuccess(true);
        setSaving(false);
        setTimeout(() => setSuccess(false), 3000);
        return;
      }

      const updated = await updateSettings(payload);
      setSettings(updated);
      setApiKey(updated.openrouter_api_key);
      setApiKeyChanged(false);
      setShowApiKey(false);
      setSuccess(true);
      setTimeout(() => setSuccess(false), 3000);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur de sauvegarde');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="p-4 sm:p-6 space-y-6">
        <div className="space-y-2">
          <div className="skeleton h-8 w-48" />
          <div className="skeleton h-4 w-72" />
        </div>
        <div className="skeleton h-64 rounded-xl" />
      </div>
    );
  }

  return (
    <div className="p-4 sm:p-6 space-y-6 max-w-2xl">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-[#1a1a1a]">Paramètres</h1>
        <p className="text-sm text-[#6b7280] mt-1">
          Configurez les paramètres de l&apos;application
        </p>
      </div>

      {/* Error alert */}
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4 flex items-start gap-3">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#dc2626" strokeWidth="1.5" strokeLinecap="round" className="flex-shrink-0 mt-0.5">
            <circle cx="10" cy="10" r="8" />
            <path d="M10 6.5V10.5" />
            <circle cx="10" cy="13.5" r="0.5" fill="#dc2626" />
          </svg>
          <div>
            <p className="text-sm font-medium text-red-800">Erreur</p>
            <p className="text-sm text-red-600 mt-0.5">{error}</p>
          </div>
        </div>
      )}

      {/* Success alert */}
      {success && (
        <div className="bg-green-50 border border-green-200 rounded-xl p-4 flex items-start gap-3">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#16a34a" strokeWidth="1.5" strokeLinecap="round" className="flex-shrink-0 mt-0.5">
            <circle cx="10" cy="10" r="8" />
            <path d="M7 10L9.5 12.5L13.5 7.5" />
          </svg>
          <p className="text-sm font-medium text-green-800">
            Paramètres sauvegardés avec succès
          </p>
        </div>
      )}

      {/* API Configuration Section */}
      <div className="bg-white border border-beige-300 rounded-xl p-4 sm:p-6 space-y-5">
        <div className="flex items-center gap-2">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#2E75B6" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="9" width="14" height="8" rx="2" />
            <path d="M6 9V6C6 3.8 7.8 2 10 2C12.2 2 14 3.8 14 6V9" />
            <circle cx="10" cy="13" r="1" fill="#2E75B6" />
          </svg>
          <h2 className="text-lg font-semibold text-[#1a1a1a]">Configuration API</h2>
        </div>

        {/* API Key */}
        <div className="space-y-1.5">
          <label htmlFor="api-key" className="block text-sm font-medium text-[#1a1a1a]">
            Clé API OpenRouter
          </label>
          <div className="relative">
            <input
              id="api-key"
              type={showApiKey ? 'text' : 'password'}
              value={apiKey}
              onChange={(e) => {
                setApiKey(e.target.value);
                setApiKeyChanged(true);
              }}
              onFocus={() => {
                // Clear masked value on focus so user can type new key
                if (!apiKeyChanged) {
                  setApiKey('');
                  setApiKeyChanged(true);
                }
              }}
              placeholder="sk-or-..."
              className="w-full px-3 py-2.5 pr-10 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
            />
            <button
              type="button"
              onClick={() => setShowApiKey(!showApiKey)}
              className="absolute right-2.5 top-1/2 -translate-y-1/2 p-1 text-[#6b7280] hover:text-[#1a1a1a] transition-colors"
              aria-label={showApiKey ? 'Masquer la clé' : 'Afficher la clé'}
            >
              {showApiKey ? (
                <svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M3 3L17 17" />
                  <path d="M10 5C13 5 16 8 17 10C16.5 11 15.5 12.5 14 13.5" />
                  <path d="M6 6.5C4.5 7.5 3.5 9 3 10C4 12 7 15 10 15C11 15 12 14.7 13 14.2" />
                </svg>
              ) : (
                <svg width="18" height="18" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M10 5C13 5 16 8 17 10C16 12 13 15 10 15C7 15 4 12 3 10C4 8 7 5 10 5Z" />
                  <circle cx="10" cy="10" r="2.5" />
                </svg>
              )}
            </button>
          </div>
          <p className="text-xs text-[#9ca3af]">
            Clé API de votre compte OpenRouter. Cliquez sur le champ pour saisir une nouvelle clé.
          </p>
        </div>

        {/* Base URL */}
        <div className="space-y-1.5">
          <label htmlFor="base-url" className="block text-sm font-medium text-[#1a1a1a]">
            URL de base OpenRouter
          </label>
          <input
            id="base-url"
            type="url"
            value={baseUrl}
            onChange={(e) => setBaseUrl(e.target.value)}
            placeholder="https://openrouter.ai/api/v1"
            className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
          />
          <p className="text-xs text-[#9ca3af]">
            Modifiez seulement si vous utilisez un proxy ou un endpoint personnalisé.
          </p>
        </div>
      </div>

      {/* AI Model Section */}
      <div className="bg-white border border-beige-300 rounded-xl p-4 sm:p-6 space-y-5">
        <div className="flex items-center gap-2">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#2E75B6" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="10" cy="10" r="7" />
            <path d="M10 6V10L13 12" />
          </svg>
          <h2 className="text-lg font-semibold text-[#1a1a1a]">Modèle IA</h2>
        </div>

        <div className="space-y-1.5">
          <label htmlFor="model" className="block text-sm font-medium text-[#1a1a1a]">
            Modèle OpenRouter
          </label>
          <input
            id="model"
            type="text"
            value={model}
            onChange={(e) => setModel(e.target.value)}
            placeholder="google/gemini-3.1-pro-preview"
            className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
          />
          <p className="text-xs text-[#9ca3af]">
            Identifiant du modèle sur OpenRouter (ex: google/gemini-3.1-pro-preview, anthropic/claude-sonnet-4).
          </p>
        </div>
      </div>

      {/* Storage Section */}
      <div className="bg-white border border-beige-300 rounded-xl p-4 sm:p-6 space-y-5">
        <div className="flex items-center gap-2">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#2E75B6" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 5C3 4 3.5 3 5 3H8L10 5H15C16.5 5 17 6 17 7V15C17 16 16.5 17 15 17H5C3.5 17 3 16 3 15V5Z" />
          </svg>
          <h2 className="text-lg font-semibold text-[#1a1a1a]">Stockage</h2>
        </div>

        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-[#1a1a1a]">
            Dossier de données
          </label>
          <div className="w-full px-3 py-2.5 bg-beige-100 border border-beige-300 rounded-lg text-sm text-[#6b7280] select-all">
            {settings?.data_dir || '/data'}
          </div>
          <p className="text-xs text-[#9ca3af]">
            Chemin du dossier contenant les documents et la base de données. Modifiable uniquement via la variable d&apos;environnement DOCUMIND_DATA_DIR.
          </p>
        </div>
      </div>

      {/* Save button — sticky on mobile */}
      <div className="sticky bottom-0 bg-beige-100 py-4 -mx-4 px-4 sm:-mx-6 sm:px-6 border-t border-beige-300 sm:border-0 sm:bg-transparent sm:static sm:py-0 sm:mx-0 sm:px-0">
        <button
          onClick={handleSave}
          disabled={saving}
          className="w-full sm:w-auto flex items-center justify-center gap-2 px-6 py-2.5 bg-accent hover:bg-accent-hover disabled:opacity-60 disabled:cursor-not-allowed text-white rounded-lg text-sm font-medium transition-colors"
        >
          {saving ? (
            <>
              <svg className="animate-spin" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
              </svg>
              Enregistrement…
            </>
          ) : (
            <>
              <svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M14 6L7.5 12.5L4 9" />
              </svg>
              Enregistrer les paramètres
            </>
          )}
        </button>
      </div>
    </div>
  );
}
