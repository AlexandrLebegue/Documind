'use client';

import { useState, useEffect, useCallback } from 'react';
import { getSettings, updateSettings, checkForUpdate, applyUpdate, triggerNasSync, testLlamaCppConnection } from '@/lib/api';
import type { Settings, UpdateCheckResult, NasSyncResult } from '@/lib/api';

export default function SettingsPage() {
  const [settings, setSettings] = useState<Settings | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  // Update state
  const [updateInfo, setUpdateInfo] = useState<UpdateCheckResult | null>(null);
  const [checkingUpdate, setCheckingUpdate] = useState(false);
  const [updating, setUpdating] = useState(false);
  const [updateError, setUpdateError] = useState<string | null>(null);
  const [updateStatus, setUpdateStatus] = useState<string | null>(null);

  // Form state
  const [provider, setProvider] = useState('openrouter');
  const [apiKey, setApiKey] = useState('');
  const [model, setModel] = useState('');
  const [baseUrl, setBaseUrl] = useState('');
  const [ollamaBaseUrl, setOllamaBaseUrl] = useState('');
  const [ollamaModel, setOllamaModel] = useState('');
  const [llamacppBaseUrl, setLlamacppBaseUrl] = useState('http://192.168.1.50:8080');
  const [llamacppModel, setLlamacppModel] = useState('local');
  const [llamacppTesting, setLlamacppTesting] = useState(false);
  const [llamacppStatus, setLlamacppStatus] = useState<'ok' | 'error' | null>(null);
  const [llamacppStatusMsg, setLlamacppStatusMsg] = useState('');
  const [showApiKey, setShowApiKey] = useState(false);
  const [apiKeyChanged, setApiKeyChanged] = useState(false);

  // NAS sync state
  const [nasEnabled, setNasEnabled] = useState(false);
  const [nasHost, setNasHost] = useState('192.168.1.100');
  const [nasShare, setNasShare] = useState('NAS_Commun_Vol2');
  const [nasPath, setNasPath] = useState('DOCUMIND/originals');
  const [nasUsername, setNasUsername] = useState('');
  const [nasPassword, setNasPassword] = useState('');
  const [nasPasswordChanged, setNasPasswordChanged] = useState(false);
  const [nasSyncHour, setNasSyncHour] = useState(7);
  const [nasSyncMinute, setNasSyncMinute] = useState(0);
  const [syncing, setSyncing] = useState(false);
  const [syncResult, setSyncResult] = useState<NasSyncResult | null>(null);
  const [syncError, setSyncError] = useState<string | null>(null);

  useEffect(() => {
    async function fetchSettings() {
      try {
        const data = await getSettings();
        setSettings(data);
        setProvider(data.ai_provider ?? 'openrouter');
        setApiKey(data.openrouter_api_key);
        setModel(data.openrouter_model);
        setBaseUrl(data.openrouter_base_url);
        setOllamaBaseUrl(data.ollama_base_url ?? 'http://localhost:11434');
        setOllamaModel(data.ollama_model ?? 'llama3.2');
        setLlamacppBaseUrl(data.llamacpp_base_url ?? 'http://192.168.1.50:8080');
        setLlamacppModel(data.llamacpp_model ?? 'local');
        setNasEnabled(data.nas_sync_enabled ?? false);
        setNasHost(data.nas_host ?? '192.168.1.100');
        setNasShare(data.nas_share ?? 'NAS_Commun_Vol2');
        setNasPath(data.nas_path ?? 'DOCUMIND/originals');
        setNasUsername(data.nas_username ?? '');
        setNasSyncHour(data.nas_sync_hour ?? 7);
        setNasSyncMinute(data.nas_sync_minute ?? 0);
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Erreur de chargement');
      } finally {
        setLoading(false);
      }
    }
    fetchSettings();
  }, []);

  const handleCheckUpdate = useCallback(async () => {
    setCheckingUpdate(true);
    setUpdateError(null);
    setUpdateStatus(null);
    try {
      const result = await checkForUpdate();
      setUpdateInfo(result);
      if (result.error) setUpdateError(result.error);
    } catch (err) {
      setUpdateError(err instanceof Error ? err.message : 'Erreur de vérification');
    } finally {
      setCheckingUpdate(false);
    }
  }, []);

  const handleApplyUpdate = async () => {
    setUpdating(true);
    setUpdateError(null);
    setUpdateStatus('Mise à jour en cours…');
    try {
      await applyUpdate();
      setUpdateStatus('Mise à jour lancée. Redémarrage en cours…');
      // Poll /api/health until the server comes back up
      const maxWait = 60_000;
      const interval = 2_000;
      const start = Date.now();
      const poll = async () => {
        if (Date.now() - start > maxWait) {
          setUpdateStatus('Le serveur met du temps à redémarrer. Actualisez la page manuellement.');
          setUpdating(false);
          return;
        }
        try {
          const res = await fetch('/api/health');
          if (res.ok) {
            setUpdateStatus('Redémarrage réussi !');
            setUpdating(false);
            setTimeout(() => window.location.reload(), 1000);
            return;
          }
        } catch {
          // Server not yet up — keep polling
        }
        setTimeout(poll, interval);
      };
      setTimeout(poll, 3000);
    } catch (err) {
      setUpdateError(err instanceof Error ? err.message : 'Erreur de mise à jour');
      setUpdating(false);
    }
  };

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    setSuccess(false);

    try {
      const payload: import('@/lib/api').SettingsUpdate = {};

      if (provider !== settings?.ai_provider) {
        payload.ai_provider = provider;
      }
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
      if (ollamaBaseUrl !== settings?.ollama_base_url) {
        payload.ollama_base_url = ollamaBaseUrl;
      }
      if (ollamaModel !== settings?.ollama_model) {
        payload.ollama_model = ollamaModel;
      }
      if (llamacppBaseUrl !== settings?.llamacpp_base_url) {
        payload.llamacpp_base_url = llamacppBaseUrl;
      }
      if (llamacppModel !== settings?.llamacpp_model) {
        payload.llamacpp_model = llamacppModel;
      }
      // NAS settings — always include to ensure cron stays in sync
      payload.nas_sync_enabled = nasEnabled;
      payload.nas_host = nasHost;
      payload.nas_share = nasShare;
      payload.nas_path = nasPath;
      payload.nas_username = nasUsername;
      payload.nas_sync_hour = nasSyncHour;
      payload.nas_sync_minute = nasSyncMinute;
      if (nasPasswordChanged && nasPassword) {
        payload.nas_password = nasPassword;
      }

      if (Object.keys(payload).length === 0) {
        setSuccess(true);
        setSaving(false);
        setTimeout(() => setSuccess(false), 3000);
        return;
      }

      const updated = await updateSettings(payload);
      setSettings(updated);
      setProvider(updated.ai_provider ?? 'openrouter');
      setApiKey(updated.openrouter_api_key);
      setOllamaBaseUrl(updated.ollama_base_url ?? 'http://localhost:11434');
      setOllamaModel(updated.ollama_model ?? 'llama3.2');
      setLlamacppBaseUrl(updated.llamacpp_base_url ?? 'http://192.168.1.50:8080');
      setLlamacppModel(updated.llamacpp_model ?? 'local');
      setNasEnabled(updated.nas_sync_enabled ?? false);
      setNasHost(updated.nas_host ?? '192.168.1.100');
      setNasShare(updated.nas_share ?? 'NAS_Commun_Vol2');
      setNasPath(updated.nas_path ?? 'DOCUMIND/originals');
      setNasUsername(updated.nas_username ?? '');
      setNasSyncHour(updated.nas_sync_hour ?? 7);
      setNasSyncMinute(updated.nas_sync_minute ?? 0);
      setApiKeyChanged(false);
      setNasPasswordChanged(false);
      setShowApiKey(false);
      setSuccess(true);
      setTimeout(() => setSuccess(false), 3000);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erreur de sauvegarde');
    } finally {
      setSaving(false);
    }
  };

  const handleNasSyncNow = useCallback(async () => {
    setSyncing(true);
    setSyncResult(null);
    setSyncError(null);
    try {
      const result = await triggerNasSync();
      setSyncResult(result);
      if (result.error_message) setSyncError(result.error_message);
    } catch (err) {
      setSyncError(err instanceof Error ? err.message : 'Erreur de synchronisation');
    } finally {
      setSyncing(false);
    }
  }, []);

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

      {/* AI Provider Section */}
      <div className="bg-white border border-beige-300 rounded-xl p-4 sm:p-6 space-y-5">
        <div className="flex items-center gap-2">
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#2E75B6" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <rect x="3" y="9" width="14" height="8" rx="2" />
            <path d="M6 9V6C6 3.8 7.8 2 10 2C12.2 2 14 3.8 14 6V9" />
            <circle cx="10" cy="13" r="1" fill="#2E75B6" />
          </svg>
          <h2 className="text-lg font-semibold text-[#1a1a1a]">Configuration IA</h2>
        </div>

        {/* Provider selector */}
        <div className="space-y-1.5">
          <label className="block text-sm font-medium text-[#1a1a1a]">Fournisseur IA</label>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
            {[
              { value: 'openrouter', label: 'OpenRouter', desc: 'API cloud (Gemini, Claude…)' },
              { value: 'ollama', label: 'Ollama', desc: 'Proxmox / local' },
              { value: 'llamacpp', label: 'llama.cpp', desc: 'VM wm-ai-llm (GTX 1060)' },
              { value: 'custom', label: 'Personnalisé', desc: 'Endpoint OpenAI-compatible' },
            ].map((p) => (
              <button
                key={p.value}
                type="button"
                onClick={() => setProvider(p.value)}
                className={`flex flex-col items-start px-3 py-2.5 rounded-lg border text-left transition-colors ${
                  provider === p.value
                    ? 'border-accent bg-accent/5 text-accent'
                    : 'border-beige-300 bg-beige-50 text-[#1a1a1a] hover:bg-beige-100'
                }`}
              >
                <span className="text-sm font-medium">{p.label}</span>
                <span className="text-xs text-[#9ca3af] mt-0.5">{p.desc}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Ollama fields */}
        {provider === 'ollama' && (
          <>
            <div className="space-y-1.5">
              <label htmlFor="ollama-url" className="block text-sm font-medium text-[#1a1a1a]">
                URL Ollama
              </label>
              <input
                id="ollama-url"
                type="url"
                value={ollamaBaseUrl}
                onChange={(e) => setOllamaBaseUrl(e.target.value)}
                placeholder="http://192.168.1.50:11434"
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
              <p className="text-xs text-[#9ca3af]">
                IP ou hostname de votre instance Ollama sur Proxmox (port 11434 par défaut).
              </p>
            </div>

            <div className="space-y-1.5">
              <label htmlFor="ollama-model" className="block text-sm font-medium text-[#1a1a1a]">
                Modèle Ollama
              </label>
              <input
                id="ollama-model"
                type="text"
                value={ollamaModel}
                onChange={(e) => setOllamaModel(e.target.value)}
                placeholder="llama3.2"
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
              <p className="text-xs text-[#9ca3af]">
                Nom du modèle tel qu&apos;affiché par <code className="font-mono">ollama list</code> (ex: llama3.2, mistral, gemma3).
              </p>
            </div>
          </>
        )}

        {/* llama.cpp fields */}
        {provider === 'llamacpp' && (
          <>
            <div className="space-y-1.5">
              <label htmlFor="llamacpp-url" className="block text-sm font-medium text-[#1a1a1a]">
                URL llama-server
              </label>
              <input
                id="llamacpp-url"
                type="url"
                value={llamacppBaseUrl}
                onChange={(e) => setLlamacppBaseUrl(e.target.value)}
                placeholder="http://192.168.1.50:8080"
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
              <p className="text-xs text-[#9ca3af]">
                Adresse du serveur llama.cpp (<code className="font-mono">llama-server --host 0.0.0.0 --port 8080</code>).
              </p>
            </div>

            <div className="space-y-1.5">
              <label htmlFor="llamacpp-model" className="block text-sm font-medium text-[#1a1a1a]">
                Nom du modèle
              </label>
              <input
                id="llamacpp-model"
                type="text"
                value={llamacppModel}
                onChange={(e) => setLlamacppModel(e.target.value)}
                placeholder="local"
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
              <p className="text-xs text-[#9ca3af]">
                Laisser <code className="font-mono">local</code> si un seul modèle est chargé dans llama-server.
              </p>
            </div>

            {/* Test connection button */}
            <div className="flex items-center gap-3">
              <button
                type="button"
                disabled={llamacppTesting}
                onClick={async () => {
                  setLlamacppTesting(true);
                  setLlamacppStatus(null);
                  try {
                    const r = await testLlamaCppConnection();
                    if (r.status === 'ok') {
                      setLlamacppStatus('ok');
                      setLlamacppStatusMsg('Connexion réussie');
                    } else {
                      setLlamacppStatus('error');
                      setLlamacppStatusMsg(String(r.detail ?? 'Erreur inconnue'));
                    }
                  } catch (e) {
                    setLlamacppStatus('error');
                    setLlamacppStatusMsg(e instanceof Error ? e.message : 'Erreur de connexion');
                  } finally {
                    setLlamacppTesting(false);
                  }
                }}
                className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium bg-zinc-100 hover:bg-zinc-200 text-zinc-700 border border-zinc-200 transition-colors disabled:opacity-50"
              >
                {llamacppTesting ? (
                  <svg className="animate-spin" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" /></svg>
                ) : (
                  <svg width="14" height="14" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><path d="M3 10a7 7 0 1 0 14 0A7 7 0 0 0 3 10Z"/><path d="M10 7v6M7 10h6"/></svg>
                )}
                Tester la connexion
              </button>
              {llamacppStatus === 'ok' && (
                <span className="text-sm text-green-600 font-medium">✓ {llamacppStatusMsg}</span>
              )}
              {llamacppStatus === 'error' && (
                <span className="text-sm text-red-600">{llamacppStatusMsg}</span>
              )}
            </div>
          </>
        )}

        {/* OpenRouter fields */}
        {(provider === 'openrouter' || provider === 'custom') && (
          <>
            <div className="space-y-1.5">
              <label htmlFor="api-key" className="block text-sm font-medium text-[#1a1a1a]">
                Clé API
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
                    if (!apiKeyChanged) {
                      setApiKey('');
                      setApiKeyChanged(true);
                    }
                  }}
                  placeholder={provider === 'openrouter' ? 'sk-or-...' : 'Bearer token ou clé API'}
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
                {provider === 'openrouter'
                  ? 'Clé API de votre compte OpenRouter. Cliquez sur le champ pour saisir une nouvelle clé.'
                  : 'Clé d\'authentification pour votre endpoint personnalisé.'}
              </p>
            </div>

            <div className="space-y-1.5">
              <label htmlFor="base-url" className="block text-sm font-medium text-[#1a1a1a]">
                {provider === 'openrouter' ? 'URL de base OpenRouter' : 'URL de base'}
              </label>
              <input
                id="base-url"
                type="url"
                value={baseUrl}
                onChange={(e) => setBaseUrl(e.target.value)}
                placeholder={provider === 'openrouter' ? 'https://openrouter.ai/api/v1' : 'https://my-llm-proxy/v1'}
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
              <p className="text-xs text-[#9ca3af]">
                {provider === 'openrouter'
                  ? 'Modifiez seulement si vous utilisez un proxy ou un endpoint personnalisé.'
                  : 'URL de base de votre endpoint OpenAI-compatible (sans /chat/completions).'}
              </p>
            </div>

            <div className="space-y-1.5">
              <label htmlFor="model" className="block text-sm font-medium text-[#1a1a1a]">
                Modèle
              </label>
              <input
                id="model"
                type="text"
                value={model}
                onChange={(e) => setModel(e.target.value)}
                placeholder={provider === 'openrouter' ? 'google/gemini-3.1-pro-preview' : 'gpt-4o'}
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
              <p className="text-xs text-[#9ca3af]">
                {provider === 'openrouter'
                  ? 'Identifiant du modèle sur OpenRouter (ex: google/gemini-3.1-pro-preview, anthropic/claude-sonnet-4).'
                  : 'Identifiant du modèle exposé par votre endpoint.'}
              </p>
            </div>
          </>
        )}
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

      {/* NAS Sync Section */}
      <div className="bg-white border border-beige-300 rounded-xl p-4 sm:p-6 space-y-5">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#2E75B6" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <rect x="2" y="6" width="16" height="10" rx="2" />
              <path d="M6 6V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v1" />
              <path d="M10 10v4M8 12l2 2 2-2" />
            </svg>
            <h2 className="text-lg font-semibold text-[#1a1a1a]">Synchronisation NAS</h2>
          </div>
          {/* Toggle */}
          <button
            type="button"
            role="switch"
            aria-checked={nasEnabled}
            onClick={() => setNasEnabled(!nasEnabled)}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
              nasEnabled ? 'bg-accent' : 'bg-beige-300'
            }`}
          >
            <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${
              nasEnabled ? 'translate-x-6' : 'translate-x-1'
            }`} />
          </button>
        </div>

        <p className="text-xs text-[#9ca3af]">
          Monte automatiquement le partage réseau (CIFS/SMB) et importe les nouveaux documents dans Documind.
          Le crontab du serveur est mis à jour dès que vous sauvegardez.
        </p>

        {/* Sync result */}
        {syncError && (
          <div className="bg-red-50 border border-red-200 rounded-lg px-3 py-2 text-sm text-red-700">
            {syncError}
          </div>
        )}
        {syncResult && !syncError && (
          <div className="bg-green-50 border border-green-200 rounded-lg px-3 py-2 text-sm text-green-800 space-y-1">
            <p className="font-medium">Sync terminée</p>
            <p>Scannés : {syncResult.scanned} · Importés : {syncResult.imported} · Ignorés : {syncResult.skipped} · Erreurs : {syncResult.errors}</p>
            {syncResult.files_imported.length > 0 && (
              <p className="text-xs text-green-700">Importés : {syncResult.files_imported.join(', ')}</p>
            )}
            {syncResult.files_errors.length > 0 && (
              <p className="text-xs text-red-600">Erreurs : {syncResult.files_errors.join(', ')}</p>
            )}
          </div>
        )}

        <div className={`space-y-4 transition-opacity ${nasEnabled ? 'opacity-100' : 'opacity-40 pointer-events-none'}`}>
          {/* NAS host + share */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-[#1a1a1a]">Hôte NAS</label>
              <input
                type="text"
                value={nasHost}
                onChange={(e) => setNasHost(e.target.value)}
                placeholder="192.168.1.100"
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
            </div>
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-[#1a1a1a]">Partage (share)</label>
              <input
                type="text"
                value={nasShare}
                onChange={(e) => setNasShare(e.target.value)}
                placeholder="NAS_Commun_Vol2"
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
            </div>
          </div>

          {/* Path */}
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-[#1a1a1a]">Chemin dans le partage</label>
            <input
              type="text"
              value={nasPath}
              onChange={(e) => setNasPath(e.target.value)}
              placeholder="DOCUMIND/originals"
              className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
            />
            <p className="text-xs text-[#9ca3af]">
              Chemin relatif à la racine du partage (ex: <code className="font-mono">DOCUMIND/originals</code>).
            </p>
          </div>

          {/* Credentials */}
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-[#1a1a1a]">Utilisateur NAS</label>
              <input
                type="text"
                value={nasUsername}
                onChange={(e) => setNasUsername(e.target.value)}
                placeholder="Alex"
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
            </div>
            <div className="space-y-1.5">
              <label className="block text-sm font-medium text-[#1a1a1a]">Mot de passe NAS</label>
              <input
                type="password"
                value={nasPassword}
                onChange={(e) => { setNasPassword(e.target.value); setNasPasswordChanged(true); }}
                onFocus={() => { if (!nasPasswordChanged) setNasPassword(''); }}
                placeholder="••••••••"
                className="w-full px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] placeholder-[#9ca3af] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              />
            </div>
          </div>

          {/* Schedule */}
          <div className="space-y-1.5">
            <label className="block text-sm font-medium text-[#1a1a1a]">Heure de synchronisation quotidienne</label>
            <div className="flex items-center gap-2">
              <select
                value={nasSyncHour}
                onChange={(e) => setNasSyncHour(Number(e.target.value))}
                className="px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              >
                {Array.from({ length: 24 }, (_, i) => (
                  <option key={i} value={i}>{String(i).padStart(2, '0')}h</option>
                ))}
              </select>
              <span className="text-sm text-[#6b7280]">:</span>
              <select
                value={nasSyncMinute}
                onChange={(e) => setNasSyncMinute(Number(e.target.value))}
                className="px-3 py-2.5 bg-beige-50 border border-beige-300 rounded-lg text-sm text-[#1a1a1a] focus:outline-none focus:ring-2 focus:ring-accent/30 focus:border-accent transition-colors"
              >
                {[0, 15, 30, 45].map((m) => (
                  <option key={m} value={m}>{String(m).padStart(2, '0')}</option>
                ))}
              </select>
              <span className="text-xs text-[#9ca3af] ml-1">
                Cron : <code className="font-mono">{nasSyncMinute} {nasSyncHour} * * *</code>
              </span>
            </div>
          </div>

          {/* Manual sync button */}
          <button
            type="button"
            onClick={handleNasSyncNow}
            disabled={syncing}
            className="flex items-center gap-2 px-4 py-2 bg-beige-100 hover:bg-beige-200 disabled:opacity-50 disabled:cursor-not-allowed text-[#1a1a1a] rounded-lg text-sm font-medium transition-colors border border-beige-300"
          >
            {syncing ? (
              <svg className="animate-spin" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
              </svg>
            ) : (
              <svg width="15" height="15" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M4 10a6 6 0 1 0 6-6" />
                <path d="M4 4v6h6" />
              </svg>
            )}
            {syncing ? 'Synchronisation…' : 'Synchroniser maintenant'}
          </button>
        </div>
      </div>

      {/* Update Section */}
      <div className="bg-white border border-beige-300 rounded-xl p-4 sm:p-6 space-y-4">
        <div className="flex items-center justify-between gap-2">
          <div className="flex items-center gap-2">
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#2E75B6" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M4 10a6 6 0 1 0 6-6" />
              <path d="M4 4v6h6" />
            </svg>
            <h2 className="text-lg font-semibold text-[#1a1a1a]">Mises à jour</h2>
          </div>
          {settings?.version && settings.version !== 'unknown' && (
            <span className="text-xs font-mono text-[#6b7280] bg-beige-100 border border-beige-200 px-2 py-1 rounded-md">
              v{settings.version}
            </span>
          )}
        </div>

        {/* Error */}
        {updateError && (
          <div className="bg-red-50 border border-red-200 rounded-lg px-3 py-2 text-sm text-red-700">
            {updateError}
          </div>
        )}

        {/* Status */}
        {updateStatus && !updateError && (
          <div className="bg-blue-50 border border-blue-200 rounded-lg px-3 py-2 text-sm text-blue-700 flex items-center gap-2">
            {updating && (
              <svg className="animate-spin flex-shrink-0" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
              </svg>
            )}
            {updateStatus}
          </div>
        )}

        {/* Commit info */}
        {updateInfo && !updateInfo.error && (
          <div className="flex items-center gap-3 text-xs text-[#6b7280] bg-beige-50 border border-beige-200 rounded-lg px-3 py-2">
            <span>Local : <code className="font-mono text-[#1a1a1a]">{updateInfo.local_commit}</code></span>
            <span>·</span>
            <span>GitHub : <code className="font-mono text-[#1a1a1a]">{updateInfo.remote_commit}</code></span>
            {!updateInfo.up_to_date && (
              <>
                <span>·</span>
                <span className="text-amber-600 font-medium">{updateInfo.behind_by} commit{updateInfo.behind_by > 1 ? 's' : ''} en retard</span>
              </>
            )}
            {updateInfo.up_to_date && (
              <>
                <span>·</span>
                <span className="text-green-600 font-medium">À jour</span>
              </>
            )}
          </div>
        )}

        <div className="flex flex-wrap gap-3">
          {/* Check button */}
          <button
            onClick={handleCheckUpdate}
            disabled={checkingUpdate || updating}
            className="flex items-center gap-2 px-4 py-2 bg-beige-100 hover:bg-beige-200 disabled:opacity-50 disabled:cursor-not-allowed text-[#1a1a1a] rounded-lg text-sm font-medium transition-colors border border-beige-300"
          >
            {checkingUpdate ? (
              <svg className="animate-spin" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
              </svg>
            ) : (
              <svg width="15" height="15" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                <path d="M4 10a6 6 0 1 0 6-6" />
                <path d="M4 4v6h6" />
              </svg>
            )}
            {checkingUpdate ? 'Vérification…' : 'Vérifier les mises à jour'}
          </button>

          {/* Apply button — only shown when an update is available */}
          {updateInfo && !updateInfo.up_to_date && !updateInfo.error && (
            <button
              onClick={handleApplyUpdate}
              disabled={updating || checkingUpdate}
              className="flex items-center gap-2 px-4 py-2 bg-accent hover:bg-accent-hover disabled:opacity-50 disabled:cursor-not-allowed text-white rounded-lg text-sm font-medium transition-colors"
            >
              {updating ? (
                <svg className="animate-spin" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83" />
                </svg>
              ) : (
                <svg width="15" height="15" viewBox="0 0 20 20" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M10 3v14M5 8l5-5 5 5" />
                </svg>
              )}
              {updating ? 'Mise à jour…' : `Mettre à jour (${updateInfo.behind_by} commit${updateInfo.behind_by > 1 ? 's' : ''})`}
            </button>
          )}
        </div>

        <p className="text-xs text-[#9ca3af]">
          Compare la branche <code className="font-mono">main</code> locale avec GitHub. La mise à jour effectue un <code className="font-mono">git pull</code>, reinstalle les dépendances, puis redémarre le serveur automatiquement.
        </p>
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
