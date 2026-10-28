'use client';

import { useCallback, useEffect, useState } from 'react';
import { isDesktopApp, normalizeServerAddress } from '@/lib/api';
import { loadServerAddress, saveServerAddress } from '@/lib/serverStore';

type Phase = 'loading' | 'setup' | 'transition' | 'ready';

async function probeServer(server: string): Promise<{ ok: boolean; message: string }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch(`${server}/api/system`, {
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    });
    if (!response.ok) {
      return { ok: false, message: `Le serveur a répondu ${response.status}. Vérifiez l'adresse.` };
    }
    await response.json();
    return { ok: true, message: '' };
  } catch {
    return {
      ok: false,
      message: 'Serveur injoignable. Vérifiez l\'adresse, le port et que DocuMind est démarré.',
    };
  } finally {
    clearTimeout(timer);
  }
}

function GeometricTransition() {
  return (
    <div className="fixed inset-0 z-[100] flex items-center justify-center bg-beige-100 geo-overlay">
      <svg width="240" height="240" viewBox="0 0 240 240" aria-hidden="true">
        <g className="geo-lines" stroke="#2E75B6" strokeWidth="2" fill="none">
          <line x1="30" y1="120" x2="210" y2="120" />
          <line x1="120" y1="30" x2="120" y2="210" />
        </g>
        <g fill="#2E75B6">
          <rect className="geo-diamond geo-d1" x="102" y="102" width="36" height="36" rx="3" />
          <rect className="geo-diamond geo-d2" x="40" y="102" width="36" height="36" rx="3" />
          <rect className="geo-diamond geo-d3" x="164" y="102" width="36" height="36" rx="3" />
          <rect className="geo-diamond geo-d4" x="102" y="40" width="36" height="36" rx="3" />
          <rect className="geo-diamond geo-d5" x="102" y="164" width="36" height="36" rx="3" />
        </g>
      </svg>
    </div>
  );
}

function SetupScreen({
  initialServer,
  initialError,
  busy,
  onConnect,
}: {
  initialServer: string;
  initialError: string;
  busy: boolean;
  onConnect: (server: string) => Promise<string | null>;
}) {
  const [value, setValue] = useState(initialServer);
  const [error, setError] = useState(initialError);

  useEffect(() => setError(initialError), [initialError]);

  const submit = async (event: React.FormEvent) => {
    event.preventDefault();
    setError('');
    const message = await onConnect(value);
    if (message) setError(message);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-gradient-to-br from-beige-100 via-beige-50 to-beige-200 px-6">
      <div className="w-full max-w-lg text-center animate-scale-in">
        <div className="mx-auto mb-8 flex h-20 w-20 items-center justify-center rounded-3xl bg-white shadow-lg shadow-beige-300/60">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/icon-192.png" alt="DocuMind" className="h-14 w-14 rounded-2xl object-cover" />
        </div>
        <h1 className="text-3xl font-bold tracking-tight text-[#1a1a1a]">DocuMind</h1>
        <p className="mt-3 text-base text-[#6b7280]">
          Adresse de votre serveur DocuMind
        </p>
        <form onSubmit={submit} className="mt-8">
          <input
            autoFocus
            value={value}
            onChange={(event) => setValue(event.target.value)}
            placeholder="192.168.1.50:8000"
            spellCheck={false}
            autoCapitalize="none"
            autoCorrect="off"
            className="w-full rounded-2xl border border-beige-300 bg-white px-6 py-4 text-center text-lg text-[#1a1a1a] shadow-sm outline-none transition focus:border-accent focus:ring-4 focus:ring-accent/15"
            aria-label="Adresse de votre serveur DocuMind"
          />
          {error && (
            <p className="mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </p>
          )}
          <button
            type="submit"
            disabled={busy || !value.trim()}
            className="mt-6 w-full rounded-2xl bg-accent px-6 py-4 text-base font-semibold text-white shadow-lg shadow-accent/25 transition hover:bg-accent-hover disabled:cursor-not-allowed disabled:opacity-60"
          >
            {busy ? 'Connexion…' : 'Se connecter'}
          </button>
        </form>
        <p className="mt-6 text-xs text-[#9ca3af]">
          Exemple : 192.168.1.50:8000 — l&apos;adresse est mémorisée sur cet ordinateur.
        </p>
      </div>
    </div>
  );
}

export default function DesktopGate({ children }: { children: React.ReactNode }) {
  const [desktop, setDesktop] = useState(false);
  const [phase, setPhase] = useState<Phase>('loading');
  const [server, setServer] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!isDesktopApp()) {
      setDesktop(false);
      setPhase('ready');
      return;
    }
    setDesktop(true);
    let cancelled = false;
    (async () => {
      const stored = await loadServerAddress();
      if (cancelled) return;
      setServer(stored);
      if (!stored) {
        setPhase('setup');
        return;
      }
      const probe = await probeServer(stored);
      if (cancelled) return;
      if (probe.ok) {
        setPhase('transition');
      } else {
        setError(probe.message);
        setPhase('setup');
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    const reset = () => {
      setPhase('setup');
      setError('');
    };
    window.addEventListener('documind-change-server', reset);
    return () => window.removeEventListener('documind-change-server', reset);
  }, []);

  useEffect(() => {
    if (phase !== 'transition') return;
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const timer = setTimeout(() => setPhase('ready'), reduced ? 180 : 950);
    return () => clearTimeout(timer);
  }, [phase]);

  const connect = useCallback(async (value: string): Promise<string | null> => {
    const address = normalizeServerAddress(value);
    if (!address) return 'Saisissez une adresse.';
    setBusy(true);
    const probe = await probeServer(address);
    setBusy(false);
    if (!probe.ok) return probe.message;
    await saveServerAddress(address);
    setServer(address);
    setError('');
    setPhase('transition');
    return null;
  }, []);

  if (!desktop || phase === 'ready') {
    return <>{children}</>;
  }

  if (phase === 'transition') {
    return <GeometricTransition />;
  }

  if (phase === 'loading') {
    return (
      <div className="fixed inset-0 flex items-center justify-center bg-beige-100">
        <div className="h-8 w-8 animate-spin rounded-full border-2 border-beige-300 border-t-accent" />
      </div>
    );
  }

  return (
    <SetupScreen
      initialServer={server}
      initialError={error}
      busy={busy}
      onConnect={connect}
    />
  );
}
