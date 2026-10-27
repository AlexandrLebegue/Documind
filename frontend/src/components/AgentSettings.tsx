'use client';

import { useCallback, useEffect, useRef, useState } from 'react';
import { getConfiguredServer, isDesktopApp } from '@/lib/api';
import { toast } from '@/components/Toast';
import { invoke as call } from '@tauri-apps/api/core';

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
  next_run?: string | null;
  phase?: string;
  logs?: string[];
  service_error?: string | null;
  config_applied?: boolean;
  counters: { seen: number; errors: number; sent: number; accepted: number; rejected: number; ignored: number };
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
  return call<T>(command, args);
}

export default function AgentSettings() {
  const configRef = useRef<AgentConfig | null>(null);
  const writes = useRef<Promise<unknown>>(Promise.resolve());
  const polling = useRef(false);
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
      if (polling.current) return;
      polling.current = true;
      const st = await invoke<AgentStatus>('agent_status');
      setStatus(st);
      setError(null);
      return st;
    } catch (err) {
      setError(String(err));
    } finally {
      polling.current = false;
    }
  }, []);

  useEffect(() => {
    if (!desktop) return;
    let cancelled = false;
    invoke<AgentConfig>('agent_get_config').then((cfg) => {
      if (!cancelled && !configRef.current) {
        configRef.current = cfg;
        setConfig(cfg);
      }
    }).catch((err) => { if (!cancelled) { setError(String(err)); toast(String(err), 'error'); } });
    refresh();
    const timer = setInterval(refresh, 1000);
    return () => { cancelled = true; clearInterval(timer); };
  }, [desktop, refresh]);

  if (!desktop) return null;

  const update = (patch: Partial<AgentConfig>) => {
    const current = configRef.current;
    if (!current) return;
    const next = { ...current, ...patch, server: getConfiguredServer() || current.server };
    configRef.current = next;
    setConfig(next);
    writes.current = writes.current.catch(() => undefined).then(() => invoke('agent_set_config', { config: next }));
    void writes.current.catch((err) => {
      setError(`Configuration non enregistrée : ${String(err)}`);
      toast(String(err), 'error');
    });
  };

  const save = async () => {
    if (!config) return;
    setBusy('save');
    try {
      await writes.current.catch(() => undefined);
      await invoke('agent_set_config', { config: configRef.current });
      setError(null);
      toast('Configuration de synchronisation enregistrée', 'success');
      await refresh();
    } catch (err) {
      toast(String(err), 'error');
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
      if (folder && configRef.current && !configRef.current.folders.includes(folder)) {
        update({ folders: [...configRef.current!.folders, folder] });
      }
    } catch (err) {
      toast(String(err), 'error');
    }
  };

  const syncNow = async () => {
    setBusy('sync');
    try {
      await writes.current;
      await invoke('agent_set_config', { config: { ...configRef.current, server: getConfiguredServer() } });
      await invoke('agent_sync_now');
      const result = await refresh();
      const c = result?.counters;
      toast(c ? `Synchronisation terminée : ${c.seen || 0} vus, ${c.ignored || 0} ignorés, ${c.sent || 0} envoyés, ${c.accepted || 0} acceptés, ${c.rejected || 0} refusés, ${c.errors || 0} erreurs` : 'Synchronisation terminée', 'success');
    } catch (err) {
      setError(String(err));
      toast(String(err), 'error');
      await refresh();
    } finally {
      setBusy(null);
    }
  };

  const serviceAction = async (action: 'install' | 'uninstall') => {
    setBusy(action);
    try {
      if (action === 'install') {
        await writes.current;
        await invoke('agent_set_config', { config: configRef.current });
      }
      await invoke(action === 'install' ? 'agent_install' : 'agent_uninstall');
      toast(action === 'install' ? 'Service installé' : 'Service désinstallé', 'success');
      await refresh();
    } catch (err) {
      toast(String(err), 'error');
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
              <p className="text-xs text-[#6b7280]">Modifications enregistrées automatiquement sur ce PC. Après modification, appliquez la configuration au service pour activer la synchronisation.</p>
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
              <button onClick={syncNow} disabled={busy !== null} className="min-h-[44px] rounded-lg bg-accent px-5 text-sm font-medium text-white disabled:opacity-60">
                {busy === 'sync' ? 'Synchronisation en cours…' : 'Synchroniser maintenant'}
              </button>
              <button
                onClick={save}
                disabled={busy !== null}
                className="min-h-[44px] rounded-lg bg-accent px-5 text-sm font-medium text-white hover:bg-accent-hover disabled:opacity-60"
              >
                {busy === 'save' ? 'Enregistrement…' : 'Enregistrer la configuration'}
              </button>
              {status?.installed ? (<>
                <button
                  onClick={() => serviceAction('uninstall')}
                  disabled={busy !== null}
                  className="min-h-[44px] rounded-lg border border-red-300 px-5 text-sm font-medium text-red-700 hover:bg-red-50 disabled:opacity-60"
                >
                  {busy === 'uninstall' ? 'Désinstallation…' : 'Désinstaller le service'}
                </button>
                <button onClick={() => serviceAction('install')} disabled={busy !== null} className="rounded-lg border px-5 py-2 disabled:opacity-60">Appliquer au service (administrateur)</button>
              </>) : (
                <button
                  onClick={() => serviceAction('install')}
                  disabled={busy !== null}
                  className="min-h-[44px] rounded-lg border border-beige-300 px-5 text-sm font-medium text-[#1a1a1a] hover:bg-beige-50 disabled:opacity-60"
                >
                  {busy === 'install' ? 'Installation…' : 'Installer / appliquer au service'}
                </button>
              )}
            </div>

            {busy === 'sync' && <div role="status" aria-live="polite" className="rounded-lg border p-3">
              <progress aria-label="Synchronisation en cours" className="w-full" />
              {status?.phase || 'Démarrage de l’agent…'} · {status?.counters.seen || 0} fichiers vus · {status?.counters.sent || 0} envoyés
            </div>}
            {status && (
              <div className="grid gap-3 rounded-lg border border-beige-300 bg-beige-50 p-4 text-sm sm:grid-cols-2">
                <p>
                  <span className="text-[#6b7280]">Service :</span>{' '}
                  <span className={status.running ? 'font-medium text-green-700' : 'font-medium text-[#6b7280]'}>
                    {status.service_error ? `erreur : ${status.service_error}` : status.installed ? (status.running ? 'démarré' : 'installé, arrêté') : 'non installé'}
                  </span>
                </p>
                <p>
                  <span className="text-[#6b7280]">Dernier passage :</span>{' '}
                  {status.last_run ? new Date(status.last_run).toLocaleString('fr-FR') : '—'}
                </p>
                <p>Prochain passage : {status.running && status.next_run ? new Date(status.next_run).toLocaleString('fr-FR') : '—'}</p>
                <p className="sm:col-span-2">{status.phase || 'Aucun passage enregistré'}</p>
                {status.config_applied === false && <p className="sm:col-span-2 text-amber-700">Configuration locale différente de celle du service. Cliquez sur Installer / appliquer au service pour activer ces dossiers en automatique. Le lancement manuel utilise vos réglages actuels.</p>}
                <p className="sm:col-span-2 text-[#6b7280]">
                  Dernier passage : vus <strong>{status.counters.seen || 0}</strong> · erreurs <strong>{status.counters.errors || 0}</strong> · envoyés <strong className="text-[#1a1a1a]">{status.counters.sent}</strong> ·
                  acceptés <strong className="text-green-700">{status.counters.accepted}</strong> ·
                  refusés <strong className="text-red-700">{status.counters.rejected}</strong> ·
                  ignorés <strong className="text-[#1a1a1a]">{status.counters.ignored}</strong>
                </p>
                {status.last_error && (
                  <p className="sm:col-span-2 text-xs text-red-600">Dernière erreur : {status.last_error}</p>
                )}
                <div className="sm:col-span-2">
                  <p className="font-medium">Journal de l’agent — 50 dernières lignes</p>
                  <pre className="mt-2 max-h-72 overflow-auto whitespace-pre-wrap break-all rounded bg-white p-3 text-xs">{status.logs?.join('\n') || 'Aucune ligne de journal disponible.'}</pre>
                </div>
                <p className="sm:col-span-2 text-xs text-[#6b7280]">Le service Windows utilise LocalSystem : les lecteurs réseau de votre session peuvent être inaccessibles. Le lancement manuel utilise votre compte.</p>
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
