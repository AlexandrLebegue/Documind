import {
  getConfiguredServer,
  isDesktopApp,
  normalizeServerAddress,
  setConfiguredServer,
} from './api';

async function tauriInvoke<T>(command: string, args?: Record<string, unknown>): Promise<T | null> {
  if (!isDesktopApp()) return null;
  try {
    const { invoke } = await import('@tauri-apps/api/core');
    return await invoke<T>(command, args);
  } catch {
    return null;
  }
}

export async function loadServerAddress(): Promise<string> {
  if (!isDesktopApp()) return '';
  const stored = await tauriInvoke<string | null>('get_server');
  if (stored) {
    setConfiguredServer(stored);
    return normalizeServerAddress(stored);
  }
  return getConfiguredServer();
}

export async function saveServerAddress(value: string): Promise<string> {
  const address = setConfiguredServer(value);
  await tauriInvoke<void>('set_server', { server: address });
  return address;
}

export async function clearServerAddress(): Promise<void> {
  setConfiguredServer('');
  await tauriInvoke<void>('set_server', { server: '' });
}
