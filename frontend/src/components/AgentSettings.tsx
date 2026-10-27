'use client';

import { useCallback, useEffect, useState } from 'react';
import { getConfiguredServer, isDesktopApp } from '@/lib/api';
import { toast } from '@/components/Toast';

interface AgentConfig {
  server: string;
  folders: string[];
  interval_minutes: number;
  enabled: boolean;
}

interface AgentStatus {
  installed: boolean;
  running: boolean;
  last_run?: string | null;
  counters: { sent: number; accepted: number; rejected: number; ignored: number };
  last_error?: string | null;
  config_path?: string;
}

const INTERVALS = [
  { value: 15, label: '15 minutes' },
  { value: 60, label: '1 heure' },
  { value: 360, label: '6 heures' },
  { value: 1440, label: '24 heures' },
];

async function invoke<T>(command: string, args?: Record<string, unknown>): Promise<T> {
  const { invoke: call } = await import('@tauri-apps/api/core');
  return call<T>(command, args);
}

export default function AgentSettings() {
  const [desktop, setDesktop] = useState(false);
  const [server, setServer] = useState('');
  const [config, setConfig] = useState<AgentConfig | null>(null);
  const [status, setStatus] = useState<AgentStatus | null>(null);
  const [manualFolder, setManualFolder] = useState('');
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setDesktop(isDesktopApp());
    setServer(getConfiguredServer());
  }, []);

  const refresh = useCallback(async () => {
    if (!isDesktopApp()) return;
    try {
      const [cfg, st] = await Promise.all([
        invoke<AgentConfig>('agent_get_config'),
        invoke<AgentStatus>('agent_status'),
      ]);
      setConfig(cfg);
      setStatus(st);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Agent indisponible');
    }
  }, []);

  useEffect(() => {
    if (!desktop) return;
    refresh();
    const timer = setInterval(refresh, 10000);
    return () => clearInterval(timer);
  }, [desktop, refresh]);

  if (!desktop) return null;

  const update = (patch: Partial<AgentConfig>) => {
    setConfig((current) => (current ? { ...current, ...patch } : current));
  };

  const save = async () => {
    if (!config) return;
    setBusy('save');
    try {
      await invoke('agent_set_config', { config });
      toast('Configuration de synchronisation enregistrée', 'success');
      await refresh();
    } catch (err) {
      toast(err instanceof Error ? err.message : 'Enregistrement impossible', 'error');
    } finally {
      setBusy(null);
    }
  };

  const addFolder = async () => {
    const folder = manualFolder.trim();
    if (!folder || !config) return;
    if (config.folders.includes(folder)) {
      setManualFolder('');
      return;
    }
    update({ folders: [...config.folders, folder] });
    setManualFolder('');
  };

  const browse = async () => {
    try {
      const folder = await invoke<string | null>('pick_folder');
      if (folder && config && !config.folders.includes(folder)) {
        update({ folders: [...config.folders, folder] });
      }
    } catch (err) {
      toast(err instanceof Error ? err.message : 'Sélecteur indisponible', 'error');
    }
  };

  const serviceAction = async (action: 'install' | 'uninstall') => {
    setBusy(action);
    try {
      await invoke(action === 'install' ? 'agent_install' : 'agent_uninstall');
      toast(action === 'install' ? 'Service installé' : 'Service désinstallé', 'success');
      await refresh();
    } catch (err) {
      toast(err instanceof Error ? err.message : 'Action impossible', 'error');
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="space-y-5">
      <div className="bg-white border border-beige-300 rounded-xl p-4 sm:p-6 space-y-5">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2">
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="#2E75B6" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 10A7 7 0 0 1 15.5 5.5" />
              <path d="M15.5 2.5V5.5H12.5" />
              <path d="M17 10A7 7 0 0 1 4.5 14.5" />
              <path d="M4.5 17.5V14.5H7.5" />
            </svg>
            <h2 className="text-lg font-semibold text-[#1a1a1a]">Synchronisation automatique</h2>
          </div>
          {config && (
            <button
              type="button"
              role="switch"
              aria-checked={config.enabled}
              onClick={() => update({ enabled: !config.enabled })}
              className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${config.enabled ? 'bg-accent' : 'bg-beige-300'}`}
            >
              <span className={`inline-block h-4 w-4 transform rounded-full bg-white shadow transition-transform ${config.enabled ? 'translate-x-6' : 'translate-x-1'}`} />
            </button>
          )}
        </div>

        <p className="text-xs text-[#9ca3af]">
          L&apos;agent surveille les dossiers ci-dessous, filtre les fichiers (PDF, TXT, JPG, PNG, BMP + magic bytes),
          calcule leur empreinte SHA-256 et n&apos;envoie que les fichiers jamais vus par le serveur.
        </p>

        {error && <div className="rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700">{error}</div>}

        {config && (
          <>
            <div className="space-y-2">
              <label className="block text-sm font-medium text-[#1a1a1a]">Dossiers surveillés</label>
              {config.folders.length === 0 && (
                <p className="text-sm text-[#9ca3af]">Aucun dossier pour l&apos;instant.</p>
              )}
              <ul className="space-y-2">
                {config.folders.map((folder) => (
                  <li key={folder} className="flex items-center gap-2 rounded-lg border border-beige-300 bg-beige-50 px-3 py-2">
                    <span className="min-w-0 flex-1 break-all text-sm text-[#1a1a1a]">{folder}</span>
                    <button
                      onClick={() => update({ folders: config.folders.filter((item) => item !== folder) })}
                      className="min-h-[36px] rounded-lg px-3 text-sm text-red-600 hover:bg-red-50"
                    >
                      Retirer
                    </button>
                  </li>
                ))}
              </ul>
              <div className="flex flex-col gap-2 sm:flex-row">
                <input
                  value={manualFolder}
                  onChange={(event) => setManualFolder(event.target.value)}
                  onKeyDown={(event) => event.key === 'Enter' && (event.preventDefault(), addFolder())}
                  placeholder="C:\\Users\\moi\\Documents\\à archiver"
                  className="min-h-[44px] flex-1 rounded-lg border border-beige-300 bg-white px-3 text-sm outline-none focus:border-accent"
                />
                <button onClick={addFolder} className="min-h-[44px] rounded-lg border border-beige-300 px-4 text-sm font-medium hover:bg-beige-50">
                  Ajouter
                </button>
                <button onClick={browse} className="min-h-[44px] rounded-lg bg-accent px-4 text-sm font-medium text-white hover:bg-accent-hover">
                  Parcourir…
                </button>
              </div>
            </div>

            <div className="grid gap-4 sm:grid-cols-2">
              <div className="space-y-1.5">
                <label className="block text-sm font-medium text-[#1a1a1a]">Intervalle</label>
                <select
                  value={config.interval_minutes}
                  onChange={(event) => update({ interval_minutes: Number(event.target.value) })}
                  className="min-h-[44px] w-full rounded-lg border border-beige-300 bg-white px-3 text-sm outline-none focus:border-accent"
                >
                  {INTERVALS.map((item) => (
                    <option key={item.value} value={item.value}>{item.label}</option>
                  ))}
                </select>
              </div>
              <div className="space-y-1.5">
                <label className="block text-sm font-medium text-[#1a1a1a]">Serveur</label>
                <div className="flex min-h-[44px] items-center rounded-lg border border-beige-300 bg-beige-100 px-3 text-sm text-[#6b7280]">
                  {server || 'non configuré'}
                </div>
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              <button
                onClick={save}
                disabled={busy !== null}
                className="min-h-[44px] rounded-lg bg-accent px-5 text-sm font-medium text-white hover:bg-accent-hover disabled:opacity-60"
              >
                {busy === 'save' ? 'Enregistrement…' : 'Enregistrer la configuration'}
              </button>
              {status?.installed ? (
                <button
                  onClick={() => serviceAction('uninstall')}
                  disabled={busy !== null}
                  className="min-h-[44px] rounded-lg border border-red-300 px-5 text-sm font-medium text-red-700 hover:bg-red-50 disabled:opacity-60"
                >
                  {busy === 'uninstall' ? 'Désinstallation…' : 'Désinstaller le service'}
                </button>
              ) : (
                <button
                  onClick={() => serviceAction('install')}
                  disabled={busy !== null}
                  className="min-h-[44px] rounded-lg border border-beige-300 px-5 text-sm font-medium text-[#1a1a1a] hover:bg-beige-50 disabled:opacity-60"
                >
                  {busy === 'install' ? 'Installation…' : 'Installer le service'}
                </button>
              )}
            </div>

            {status && (
              <div className="grid gap-3 rounded-lg border border-beige-300 bg-beige-50 p-4 text-sm sm:grid-cols-2">
                <p>
                  <span className="text-[#6b7280]">Service :</span>{' '}
                  <span className={status.running ? 'font-medium text-green-700' : 'font-medium text-[#6b7280]'}>
                    {status.installed ? (status.running ? 'actif' : 'installé, arrêté') : 'non installé'}
                  </span>
                </p>
                <p>
                  <span className="text-[#6b7280]">Dernier passage :</span>{' '}
                  {status.last_run ? new Date(status.last_run).toLocaleString('fr-FR') : '—'}
                </p>
                <p className="sm:col-span-2 text-[#6b7280]">
                  Envoyés <strong className="text-[#1a1a1a]">{status.counters.sent}</strong> ·
                  acceptés <strong className="text-green-700">{status.counters.accepted}</strong> ·
                  refusés <strong className="text-red-700">{status.counters.rejected}</strong> ·
                  ignorés <strong className="text-[#1a1a1a]">{status.counters.ignored}</strong>
                </p>
                {status.last_error && (
                  <p className="sm:col-span-2 text-xs text-red-600">Dernière erreur : {status.last_error}</p>
                )}
                {status.config_path && (
                  <p className="sm:col-span-2 break-all text-xs text-[#9ca3af]">Config : {status.config_path}</p>
                )}
              </div>
            )}
          </>
        )}

        <div className="border-t border-beige-300 pt-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p className="text-sm font-medium text-[#1a1a1a]">Changer de serveur</p>
              <p className="text-xs text-[#9ca3af]">Serveur actuel : {server || 'non configuré'}</p>
            </div>
            <button
              onClick={() => window.dispatchEvent(new Event('documind-change-server'))}
              className="min-h-[44px] rounded-lg border border-beige-300 px-4 text-sm font-medium text-[#1a1a1a] hover:bg-beige-50"
            >
              Changer de serveur
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
