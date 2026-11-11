import { afterEach, describe, expect, it, vi } from 'vitest';
import { matchesPattern, probeBank, probeTab, type ProbeClientOptions } from './probe-client';
import type { PageProbe } from './types';

const options: ProbeClientOptions = { timeoutMs: 200, retries: 3, retryDelayMs: 5 };

const probe = (count: number, url = 'https://online.sberbank.ru/app/loyalty/main/categories/select'): PageProbe => ({
  bankId: 'sber', title: 'Категории', url, readyState: 'complete',
  authenticationStatus: count ? 'authenticated' : 'unknown',
  selection: { isLocked: null, selectedCount: 0, visibleCount: count, maxSelectable: null, totalOptions: null, groups: [] },
  categories: Array.from({ length: count }, (_, index) => ({
    type: 'standard' as const, name: `Категория ${index}`, percent: 5, percentLabel: '5%', subtitle: null,
    description: null, iconUrl: null, iconBackgroundColor: null, selected: false, group: null, expiresInLabel: null,
  })),
  capture: { mode: 'thorough', stable: true, waitedMs: 100, reads: 3, advances: 0 },
});

function stubBrowser(sendMessage: (tabId: number, message: unknown) => Promise<unknown>, extra: Record<string, unknown> = {}) {
  const executeScript = vi.fn(async () => []);
  vi.stubGlobal('browser', {
    tabs: {
      sendMessage: vi.fn(sendMessage),
      get: vi.fn(async (tabId: number) => ({ id: tabId, status: 'complete', url: 'https://online.sberbank.ru/app/loyalty/main/categories' })),
      query: vi.fn(async () => [{ id: 1, url: 'https://online.sberbank.ru/app/loyalty/main/categories' }]),
      ...extra,
    },
    runtime: {
      getManifest: () => ({
        content_scripts: [
          { matches: ['https://online.sberbank.ru/*'], js: ['content-scripts/sber.js'] },
          { matches: ['https://online.sberbank.ru/*'], js: ['content-scripts/extended.js'] },
          { matches: ['https://www.tbank.ru/*'], js: ['content-scripts/tbank-api-bridge.js'], world: 'MAIN' },
        ],
      }),
    },
    scripting: { executeScript },
  });
  return { executeScript };
}

afterEach(() => vi.unstubAllGlobals());

describe('probeTab', () => {
  it('retries when a navigation closed the message channel', async () => {
    let calls = 0;
    stubBrowser(async () => {
      calls += 1;
      if (calls < 3) throw new Error('A listener indicated an asynchronous response by returning true, but the message channel closed before a response was received');
      return probe(4);
    });
    const result = await probeTab({ id: 1 }, 'sber', 'thorough', options);
    expect(result.kind).toBe('probe');
    expect(calls).toBe(3);
  });

  it('injects the bank script into a tab opened before the extension was loaded', async () => {
    let injected = false;
    const { executeScript } = stubBrowser(async () => {
      if (!injected) throw new Error('Could not establish connection. Receiving end does not exist.');
      return probe(2);
    });
    executeScript.mockImplementation(async () => { injected = true; return []; });

    const result = await probeTab({ id: 7 }, 'sber', 'thorough', options);

    expect(result.kind).toBe('probe');
    expect(executeScript).toHaveBeenCalledWith({ target: { tabId: 7 }, files: ['content-scripts/sber.js'] });
  });

  it('does not hang the panel when a page never answers', async () => {
    stubBrowser(() => new Promise(() => undefined));
    const started = Date.now();
    const result = await probeTab({ id: 1 }, 'sber', 'passive', options);
    expect(result).toMatchObject({ kind: 'failed', noReceiver: false });
    expect(Date.now() - started).toBeLessThan(1000);
  });

  it('reports a content-script error instead of an empty list', async () => {
    stubBrowser(async () => ({ error: 'TypeError: boom' }));
    const result = await probeTab({ id: 1 }, 'sber', 'passive', { ...options, retries: 0 });
    expect(result).toEqual({ kind: 'failed', error: 'TypeError: boom', noReceiver: false });
  });
});

describe('probeBank', () => {
  it('prefers the tab with the most categories', async () => {
    stubBrowser(async (tabId) => tabId === 2 ? probe(6) : probe(1, 'https://online.sberbank.ru/app/loyalty/main'), {
      query: vi.fn(async () => [{ id: 1 }, { id: 2 }]),
    });
    const outcome = await probeBank('sber', 'passive');
    expect(outcome.status).toBe('ready');
    expect(outcome.probe?.categories).toHaveLength(6);
  });

  it('asks for sign-in when only a login tab answers without categories', async () => {
    stubBrowser(async () => probe(0, 'https://online.sberbank.ru/CSAFront/index.do'), {
      query: vi.fn(async () => [{ id: 1, url: 'https://online.sberbank.ru/CSAFront/index.do' }]),
    });
    expect((await probeBank('sber', 'passive')).status).toBe('auth');
  });

  it('warns when the list may still have been loading', async () => {
    const unstable = { ...probe(3), capture: { mode: 'passive' as const, stable: false, waitedMs: 3500, reads: 20, advances: 0 } };
    stubBrowser(async () => unstable);
    const outcome = await probeBank('sber', 'passive');
    expect(outcome.status).toBe('ready');
    expect(outcome.message).toMatch(/неполным/);
  });
});

describe('matchesPattern', () => {
  it.each([
    ['https://online.sberbank.ru/*', 'https://online.sberbank.ru/app/x?y=1', true],
    ['https://online.sberbank.ru/*', 'https://evil.example/online.sberbank.ru/', false],
    ['https://*.yandex.ru/*', 'https://sp.yandex.ru/cashback', true],
    ['https://web.alfabank.ru/*', 'http://web.alfabank.ru/', false],
  ])('%s vs %s', (pattern, url, expected) => {
    expect(matchesPattern(pattern, url)).toBe(expected);
  });
});
