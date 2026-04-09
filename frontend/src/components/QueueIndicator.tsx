'use client';

import { useEffect, useState } from 'react';
import { getQueue, QueueStatus } from '@/lib/api';

export default function QueueIndicator() {
  const [queue, setQueue] = useState<QueueStatus | null>(null);

  useEffect(() => {
    let cancelled = false;

    async function poll() {
      try {
        const data = await getQueue();
        if (!cancelled) setQueue(data);
      } catch {
        // silently ignore polling errors
      }
    }

    poll();
    const interval = setInterval(poll, 2500);
    return () => {
      cancelled = true;
      clearInterval(interval);
    };
  }, []);

  if (!queue) return null;
  if (!queue.active && queue.total_pending === 0) return null;

  const totalJobs = queue.total_active + queue.total_pending;

  return (
    <div className="fixed bottom-4 right-4 z-50 w-80 rounded-xl border border-white/10 bg-zinc-900/95 shadow-2xl backdrop-blur-sm">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-white/10 px-4 py-2">
        <div className="flex items-center gap-2 text-sm font-medium text-white">
          <span className="relative flex h-2.5 w-2.5">
            <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-blue-400 opacity-75" />
            <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-blue-500" />
          </span>
          File de traitement
        </div>
        <span className="rounded-full bg-zinc-700 px-2 py-0.5 text-xs text-zinc-300">
          {totalJobs} {totalJobs > 1 ? 'tâches' : 'tâche'}
        </span>
      </div>

      <div className="max-h-64 overflow-y-auto px-4 py-2 space-y-1">
        {/* Active job */}
        {queue.active && (
          <div className="flex items-center gap-2 rounded-lg bg-blue-900/30 border border-blue-500/20 px-3 py-2">
            <span className="h-1.5 w-1.5 rounded-full bg-blue-400 animate-pulse flex-shrink-0" />
            <span className="min-w-0 flex-1 truncate text-xs text-blue-200">
              {queue.active.label}
            </span>
            <span className="flex-shrink-0 text-xs text-blue-400">en cours</span>
          </div>
        )}

        {/* Pending jobs */}
        {queue.pending.map((job, index) => (
          <div
            key={job.id}
            className="flex items-center gap-2 rounded-lg bg-zinc-800/60 px-3 py-2"
          >
            <span className="flex-shrink-0 text-xs font-mono text-zinc-500 w-4 text-right">
              {index + 1}
            </span>
            <span className="min-w-0 flex-1 truncate text-xs text-zinc-300">
              {job.label}
            </span>
            <span className="flex-shrink-0 text-xs text-zinc-500">en attente</span>
          </div>
        ))}
      </div>
    </div>
  );
}
