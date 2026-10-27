import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import AgentSettings from './AgentSettings';
const { invoke, toast } = vi.hoisted(() => ({ invoke: vi.fn(), toast: vi.fn() }));
vi.mock('@tauri-apps/api/core', () => ({ invoke }));
vi.mock('@/lib/api', () => ({ isDesktopApp: () => true, getConfiguredServer: () => 'http://server' }));
vi.mock('@/components/Toast', () => ({ toast }));
let saved: { server: string; folders: string[]; enabled: boolean; interval_minutes: number };
beforeEach(() => {
  saved = { server: 'http://server', folders: [], enabled: true, interval_minutes: 60 };
  invoke.mockReset(); toast.mockReset();
  invoke.mockImplementation(async (cmd, args) => {
    if (cmd === 'agent_get_config') return structuredClone(saved);
    if (cmd === 'agent_status') return { installed: false, running: false, counters: {} };
    if (cmd === 'pick_folder') return '\\\\nas\\Équipe partagée\\Archives';
    if (cmd === 'agent_set_config') saved = structuredClone(args.config);
  });
});
afterEach(() => { cleanup(); vi.useRealTimers(); });
it('persists UNC folders, survives status polling and remount', async () => {
  const view = render(<AgentSettings />);
  await screen.findByText('Aucun dossier pour l’instant.'.replace('’', "'"));
  fireEvent.click(screen.getByText('Parcourir…'));
  await waitFor(() => expect(saved.folders).toEqual(['\\\\nas\\Équipe partagée\\Archives']));
  vi.useFakeTimers();
  await act(async () => { await vi.advanceTimersByTimeAsync(11000); });
  expect(invoke.mock.calls.filter(([cmd]) => cmd === 'agent_get_config')).toHaveLength(1);
  expect(screen.getByText(saved.folders[0])).toBeTruthy();
  vi.useRealTimers(); view.unmount(); render(<AgentSettings />);
  expect(await screen.findByText(saved.folders[0])).toBeTruthy();
});
it('keeps the selected folder visible and reports persistence failure', async () => {
  render(<AgentSettings />);
  await screen.findByText("Aucun dossier pour l'instant.");
  const original = invoke.getMockImplementation()!;
  invoke.mockImplementation((cmd, args) => cmd === 'agent_set_config' ? Promise.reject('Accès refusé') : original(cmd, args));
  fireEvent.click(screen.getByText('Parcourir…'));
  await waitFor(() => expect(toast).toHaveBeenCalledWith('Accès refusé', 'error'));
  expect(screen.getByText('\\\\nas\\Équipe partagée\\Archives')).toBeTruthy();
});
