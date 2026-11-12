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

describe('Ozon collection across pages', () => {
  const ozonCategory = (name: string, extra: Partial<PageProbe['categories'][number]> = {}) => ({
    type: 'standard' as const, name, percent: 5, percentLabel: '5%', subtitle: null, description: null,
    iconUrl: null, iconBackgroundColor: null, selected: false, group: null, expiresInLabel: null, ...extra,
  });
  const ozonProbe = (url: string, categories: PageProbe['categories']): PageProbe => ({
    bankId: 'ozon', title: 'Ozon', url, readyState: 'complete', authenticationStatus: 'authenticated',
    selection: { isLocked: null, selectedCount: 0, visibleCount: categories.length, maxSelectable: null, totalOptions: null, groups: [] },
    categories, capture: { mode: 'thorough', stable: true, waitedMs: 50, reads: 2, advances: 0 },
  });
  const pages: Record<string, PageProbe> = {
    'https://finance.ozon.ru/lk/cashback': ozonProbe('https://finance.ozon.ru/lk/cashback', [
      ozonCategory('Тестовое обучение', { selected: true, confirmed: true, maxCashbackAmount: 1500, description: 'Кешбэк до 1 500 ₽' }),
    ]),
    'https://finance.ozon.ru/lk/favorite-categories-v3?type=current&fromHome=true': ozonProbe(
      'https://finance.ozon.ru/lk/favorite-categories-v3?type=current&fromHome=true',
      [ozonCategory('Тестовое обучение'), ozonCategory('Тестовые книги')],
    ),
  };

  function stubOzon(initialTabs: Array<{ id: number; url: string }>) {
    const tabs = [...initialTabs];
    let nextId = 100;
    const create = vi.fn(async ({ url }: { url: string; active: boolean }) => {
      const tab = { id: nextId++, url, status: 'complete' };
      tabs.push(tab);
      return tab;
    });
    const remove = vi.fn(async (ids: number[]) => {
      for (const id of ids) tabs.splice(tabs.findIndex((tab) => tab.id === id), 1);
    });
    stubBrowser(async (tabId) => {
      const tab = tabs.find((candidate) => candidate.id === tabId)!;
      return pages[tab.url] ?? ozonProbe(tab.url, []);
    }, {
      query: vi.fn(async () => tabs.map((tab) => ({ ...tab }))),
      get: vi.fn(async (tabId: number) => tabs.find((tab) => tab.id === tabId)),
      create,
      remove,
    });
    return { tabs, create, remove };
  }

  const fastPages = { loadTimeoutMs: 200, pollMs: 5 };

  it('opens the missing category pages in background tabs after a click, merges them and closes them', async () => {
    // The owner's own tab shows an unrelated Ozon page.
    const { tabs, create, remove } = stubOzon([{ id: 1, url: 'https://finance.ozon.ru/lk/main' }]);

    const outcome = await probeBank('ozon', 'thorough', fastPages);

    expect(create).toHaveBeenCalledTimes(2);
    expect(create.mock.calls.every(([options]) => options.active === false)).toBe(true);
    expect(remove).toHaveBeenCalledWith([100, 101]);
    expect(tabs.map((tab) => tab.url)).toEqual(['https://finance.ozon.ru/lk/main']);
    expect(outcome.status).toBe('ready');
    const categories = outcome.probe!.categories;
    expect(categories.map((category) => category.name).sort()).toEqual(['Тестовое обучение', 'Тестовые книги']);
    // The saved month (with its cap) wins over the selection list's copy.
    expect(categories.find((category) => category.name === 'Тестовое обучение'))
      .toMatchObject({ selected: true, confirmed: true, maxCashbackAmount: 1500 });
  });

  it('does not open a page the owner already has open', async () => {
    const { create } = stubOzon([
      { id: 1, url: 'https://finance.ozon.ru/lk/favorite-categories-v3?type=current&fromHome=true' },
    ]);
    await probeBank('ozon', 'thorough', fastPages);
    expect(create.mock.calls.map(([options]) => options.url)).toEqual(['https://finance.ozon.ru/lk/cashback']);
  });

  it('never opens tabs during automatic collection', async () => {
    const { create } = stubOzon([{ id: 1, url: 'https://finance.ozon.ru/lk/main' }]);
    const outcome = await probeBank('ozon', 'passive', fastPages);
    expect(create).not.toHaveBeenCalled();
    expect(outcome.status).toBe('waiting');
    expect(outcome.message).toMatch(/Собрать все/);
  });
});

describe('selection page message', () => {
  it('explains that a selection page is only read', async () => {
    const empty = { ...probe(0, 'https://online.sberbank.ru/app/loyalty/main/categories/select'), authenticationStatus: 'authenticated' as const };
    stubBrowser(async () => ({ ...empty, capture: { ...empty.capture!, selectionPage: true } }));
    const outcome = await probeBank('sber', 'passive');
    expect(outcome.status).toBe('waiting');
    expect(outcome.message).toMatch(/страница выбора категорий/);
  });
});
