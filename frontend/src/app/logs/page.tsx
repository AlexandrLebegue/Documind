'use client';

import { useEffect, useRef, useState } from 'react';
import { createLogsEventSource } from '@/lib/api';

export default function LogsPage() {
  const [lines, setLines] = useState<string[]>([]);
  const [connected, setConnected] = useState(false);
  const [paused, setPaused] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);
  const pausedRef = useRef(false);
  const esRef = useRef<EventSource | null>(null);

  pausedRef.current = paused;

  useEffect(() => {
    const es = createLogsEventSource();
    esRef.current = es;

    es.onopen = () => setConnected(true);
    es.onerror = () => setConnected(false);

    es.onmessage = (e) => {
      if (pausedRef.current) return;
      setLines((prev) => {
        const next = [...prev, e.data];
        return next.length > 2000 ? next.slice(-2000) : next;
      });
    };

    return () => {
      es.close();
      setConnected(false);
    };
  }, []);

  // Auto-scroll to bottom when new lines arrive (unless paused)
  useEffect(() => {
    if (!paused) {
      bottomRef.current?.scrollIntoView({ behavior: 'instant' });
    }
  }, [lines, paused]);

  function colorLine(line: string): string {
    if (line.includes(' ERROR')) return 'text-red-400';
    if (line.includes(' WARNING')) return 'text-yellow-400';
    if (line.includes(' INFO')) return 'text-zinc-300';
    return 'text-zinc-500';
  }

  return (
    <div className="flex flex-col h-screen bg-zinc-950 text-zinc-100 p-4 gap-3">
      {/* Header */}
      <div className="flex items-center justify-between flex-shrink-0">
        <div className="flex items-center gap-3">
          <h1 className="text-lg font-semibold">Logs backend</h1>
          <span className={`flex items-center gap-1.5 text-xs px-2 py-0.5 rounded-full ${
            connected ? 'bg-green-900/40 text-green-400' : 'bg-red-900/40 text-red-400'
          }`}>
            <span className={`h-1.5 w-1.5 rounded-full ${connected ? 'bg-green-400 animate-pulse' : 'bg-red-400'}`} />
            {connected ? 'Connecté' : 'Déconnecté'}
          </span>
          <span className="text-xs text-zinc-500">{lines.length} lignes</span>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => setPaused((p) => !p)}
            className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors ${
              paused
                ? 'bg-yellow-600 hover:bg-yellow-500 text-white'
                : 'bg-zinc-800 hover:bg-zinc-700 text-zinc-300'
            }`}
          >
            {paused ? 'Reprendre' : 'Pause'}
          </button>
          <button
            onClick={() => setLines([])}
            className="px-3 py-1.5 rounded-lg text-xs font-medium bg-zinc-800 hover:bg-zinc-700 text-zinc-300 transition-colors"
          >
            Effacer
          </button>
        </div>
      </div>

      {/* Log output */}
      <div className="flex-1 overflow-y-auto rounded-xl bg-zinc-900 border border-zinc-800 p-4 font-mono text-xs leading-relaxed">
        {lines.length === 0 ? (
          <p className="text-zinc-600 italic">En attente de logs...</p>
        ) : (
          lines.map((line, i) => (
            <div key={i} className={colorLine(line)}>
              {line}
            </div>
          ))
        )}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}
