import { findBank, type BankDefinition, type CollectPage } from '../banks/registry';
import { mergeBankProbes } from './category-merge';
import type { BankId, PageProbe, ProbeMode } from './types';
import type { ProbeResponse } from './probe-runner';

/**
 * Side-panel side of category collection: talks to the bank tabs, survives
 * SPA/full navigations and missing content scripts, and never hangs.
 */

/**
 * `issues` is set only by a clicked (thorough) collection: one Russian line
 * per page that gave no or incomplete categories, with the reason. An empty
 * array means that collection found nothing to report.
 */
export type BankProbeOutcome =
  | { status: 'ready'; probe: PageProbe; message: string | null; issues?: string[] }
  | { status: 'auth' | 'waiting' | 'error'; probe: null; message: string; issues?: string[] };

type Tab = { id?: number; url?: string; title?: string; status?: string };

/** Shown while the tab is a category-selection page that collection only reads. */
export const SELECTION_PAGE_MESSAGE =
  'Открыта страница выбора категорий — расширение её только читает и не перезагружает. ' +
  'Сохраните выбор в банке и нажмите «Собрать все»';

export type BackgroundPageOptions = {
  /** Upper bound for a background tab to finish loading. */
  loadTimeoutMs: number;
  pollMs: number;
};

export const BACKGROUND_PAGE_OPTIONS: BackgroundPageOptions = { loadTimeoutMs: 20_000, pollMs: 300 };

/** A collection page the panel opened in a background tab. */
export type OpenedPage = {
  page: CollectPage;
  /** Null when the tab could not be created. */
  id: number | null;
  /** Where the tab ended up, e.g. a sign-in page instead of the category list. */
  url: string | null;
  loaded: boolean;
};

/**
 * Opens, in background tabs, the bank's collection pages that no open tab
 * shows. Only a clicked (thorough) collection does this; automatic probes
 * never open, navigate or reload tabs.
 */
export async function openMissingCollectPages(
  bank: BankDefinition,
  tabs: Tab[],
  options: BackgroundPageOptions = BACKGROUND_PAGE_OPTIONS,
): Promise<OpenedPage[]> {
  const missing = (bank.collectPages ?? [])
    .filter((page) => !tabs.some((tab) => tab.url?.includes(page.match)));
  const opened: OpenedPage[] = [];
  for (const page of missing) {
    try {
      const tab = await browser.tabs.create({ url: page.url, active: false }) as Tab;
      opened.push({ page, id: tab.id ?? null, url: tab.url ?? null, loaded: false });
    } catch {
      // A page that cannot be opened is reported, not read.
      opened.push({ page, id: null, url: null, loaded: false });
    }
  }
  const deadline = Date.now() + options.loadTimeoutMs;
  for (const entry of opened) {
    if (entry.id == null) continue;
    for (;;) {
      const current = await browser.tabs.get(entry.id).catch(() => null) as Tab | null;
      if (!current) {
        entry.url = null;
        break;
      }
      entry.url = current.url ?? entry.url;
      if (current.status === 'complete') {
        entry.loaded = true;
        break;
      }
      if (Date.now() >= deadline) break;
      await sleep(options.pollMs);
    }
  }
  return opened;
}

export type ProbeClientOptions = {
  /** Upper bound for one tab's answer. */
  timeoutMs: number;
  /** Retries for transient failures (navigation closed the channel). */
  retries: number;
  retryDelayMs: number;
};

export const PROBE_CLIENT_OPTIONS: Record<ProbeMode, ProbeClientOptions> = {
  passive: { timeoutMs: 12_000, retries: 1, retryDelayMs: 600 },
  // Background tabs (Ozon) run timers at most once a second, so a capture,
  // a scroll walk and several detail sheets there can take well over 25 s.
  thorough: { timeoutMs: 45_000, retries: 4, retryDelayMs: 900 },
};

export const isLoginUrl = (url: string) =>
  /\/login|\/signin|\/auth\/|passport\.yandex|private\.auth\.alfabank|\/passport\/|\/apps\/auth|\/csafront\/index\.do(?:#\/?)?$/i.test(url);
export const isAuthenticationTab = (tab: { url?: string; title?: string }) =>
  isLoginUrl(tab.url ?? '') || /^(?:вход|авторизация)/i.test(tab.title ?? '');

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

const noReceiver = /Receiving end does not exist|Could not establish connection/i;
const transient = /message port closed|message channel closed|back\/forward cache|Receiving end does not exist|Could not establish connection|Frame with ID .* was removed|No tab with id/i;

class ProbeTimeout extends Error {}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return Promise.race([
    promise,
    new Promise<T>((_, reject) => {
      timer = setTimeout(() => reject(new ProbeTimeout(`Страница не ответила за ${Math.round(ms / 1000)} с`)), ms);
    }),
  ]).finally(() => clearTimeout(timer));
}

/** Minimal match-pattern check for `scheme://host/path*` manifest patterns. */
export function matchesPattern(pattern: string, url: string): boolean {
  const match = pattern.match(/^(\*|https?):\/\/([^/]+)(\/.*)$/);
  if (!match) return false;
  let parsed: URL;
  try { parsed = new URL(url); } catch { return false; }
  const [, scheme, host, path] = match;
  if (scheme !== '*' && parsed.protocol !== `${scheme}:`) return false;
  const hostOk = host === '*' || host === parsed.hostname ||
    (host!.startsWith('*.') && parsed.hostname.endsWith(host!.slice(1)));
  if (!hostOk) return false;
  const escaped = path!.replace(/[.+?^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
  return new RegExp(`^${escaped}$`).test(`${parsed.pathname}${parsed.search}`);
}

/**
 * Tabs opened before the extension was (re)loaded have no content script.
 * Injecting the bank's probe script avoids asking the user to reload the tab.
 * Only isolated-world scripts are injected; their listener registration is
 * idempotent.
 */
export async function injectProbeScripts(tabId: number, bankId: BankId, url: string): Promise<boolean> {
  const scripts = browser.runtime.getManifest().content_scripts ?? [];
  const files = scripts
    .filter((entry) => !(entry as { world?: string }).world || (entry as { world?: string }).world === 'ISOLATED')
    .filter((entry) => entry.matches?.some((pattern) => matchesPattern(pattern, url)))
    .flatMap((entry) => entry.js ?? [])
    .filter((file) => file.endsWith(`/${bankId}.js`));
  if (!files.length) return false;
  try {
    // Manifest paths are typed as plain strings; WXT narrows `files` to its
    // generated public-path union.
    const injection = { target: { tabId }, files } as unknown as Parameters<typeof browser.scripting.executeScript>[0];
    await browser.scripting.executeScript(injection);
    return true;
  } catch {
    return false;
  }
}

export type TabProbeResult =
  | { kind: 'probe'; probe: PageProbe }
  | { kind: 'failed'; error: string; noReceiver: boolean };

export async function probeTab(
  tab: Tab,
  bankId: BankId,
  mode: ProbeMode,
  options: ProbeClientOptions = PROBE_CLIENT_OPTIONS[mode],
): Promise<TabProbeResult> {
  const tabId = tab.id!;
  let injected = false;
  let lastError = '';
  let missingReceiver = false;
  for (let attempt = 0; attempt <= options.retries; attempt += 1) {
    try {
      const response = await withTimeout(
        browser.tabs.sendMessage(tabId, { type: 'cashflow:probe-page', mode }) as Promise<ProbeResponse | undefined>,
        options.timeoutMs,
      );
      if (response && 'categories' in response) return { kind: 'probe', probe: response };
      lastError = response && 'error' in response ? response.error : 'Пустой ответ страницы';
      missingReceiver = !response;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      if (error instanceof ProbeTimeout) return { kind: 'failed', error: lastError, noReceiver: false };
      missingReceiver = noReceiver.test(lastError);
      if (!transient.test(lastError)) break;
    }
    if (attempt === options.retries) break;
    if (missingReceiver && !injected) {
      // A loading page gets its scripts from the manifest; inject only into
      // a settled page that really lacks them.
      const current = await browser.tabs.get(tabId).catch(() => null);
      if (current?.status === 'complete' && current.url) {
        injected = await injectProbeScripts(tabId, bankId, current.url);
        if (injected) continue;
      }
    }
    await sleep(options.retryDelayMs);
  }
  return { kind: 'failed', error: lastError, noReceiver: missingReceiver };
}

function bestProbe(probes: PageProbe[], preferredUrlParts: string[]): PageProbe | undefined {
  return [...probes].sort((left, right) => {
    const countDifference = right.categories.length - left.categories.length;
    if (countDifference) return countDifference;
    const stableDifference = Number(right.capture?.stable ?? false) - Number(left.capture?.stable ?? false);
    if (stableDifference) return stableDifference;
    const preferredDifference = Number(preferredUrlParts.some((part) => right.url.includes(part))) -
      Number(preferredUrlParts.some((part) => left.url.includes(part)));
    if (preferredDifference) return preferredDifference;
    return Number(right.authenticationStatus === 'authentication_required') -
      Number(left.authenticationStatus === 'authentication_required');
  })[0];
}

export async function probeBank(
  bankId: BankId,
  mode: ProbeMode,
  backgroundOptions: BackgroundPageOptions = BACKGROUND_PAGE_OPTIONS,
): Promise<BankProbeOutcome> {
  const bank = findBank(bankId);
  let tabs = (await browser.tabs.query({ url: bank.tabPatterns })) as Tab[];
  const opened = mode === 'thorough' ? await openMissingCollectPages(bank, tabs, backgroundOptions) : [];
  const openedIds = opened.flatMap((entry) => entry.id != null ? [entry.id] : []);
  try {
    if (openedIds.length) tabs = (await browser.tabs.query({ url: bank.tabPatterns })) as Tab[];
    return await probeBankTabs(bank, tabs, mode, opened, backgroundOptions);
  } finally {
    if (openedIds.length) await browser.tabs.remove(openedIds).catch(() => undefined);
  }
}

function shortUrl(url: string): string {
  try {
    const parsed = new URL(url);
    return `${parsed.host}${parsed.pathname}`;
  } catch {
    return url;
  }
}

function tabLabel(bank: BankDefinition, url: string): string {
  const page = bank.collectPages?.find((candidate) => url.includes(candidate.match));
  if (page) return page.label;
  try {
    return new URL(url).pathname || url;
  } catch {
    return url || 'вкладка';
  }
}

export type TabResult = { tab: Tab; result: TabProbeResult };

function resultIssue(label: string, { tab, result }: TabResult): string | null {
  if (result.kind === 'failed') {
    return `${label}: ${result.noReceiver
      ? 'расширение не подключилось к вкладке — обновите её'
      : `страница не ответила${result.error ? ` (${result.error})` : ''}`}`;
  }
  const { probe } = result;
  const notes = probe.notes ?? [];
  if (!probe.categories.length) {
    if (probe.authenticationStatus === 'authentication_required' || isAuthenticationTab(tab)) {
      return `${label}: требуется вход`;
    }
    return `${label}: категорий нет${notes.length ? ` — ${notes.join('; ')}` : ''}`;
  }
  if (notes.length) return `${label}: ${notes.join('; ')}`;
  if (probe.capture?.stable === false) return `${label}: список ещё догружался и может быть неполным`;
  return null;
}

function categoryCount({ result }: TabResult): number {
  return result.kind === 'probe' ? result.probe.categories.length : -1;
}

/**
 * Per-page problems of a clicked collection. For banks whose categories span
 * several pages (Ozon) every page is accounted for, so a page that timed out,
 * redirected to sign-in or showed no list is no longer hidden behind the
 * other page's categories.
 */
export function collectionIssues(
  bank: BankDefinition,
  tabResults: TabResult[],
  opened: OpenedPage[],
  response: PageProbe | undefined,
  backgroundOptions: BackgroundPageOptions = BACKGROUND_PAGE_OPTIONS,
): string[] {
  const issues: string[] = [];
  const urlOf = ({ tab, result }: TabResult) => result.kind === 'probe' ? result.probe.url : tab.url ?? '';
  const add = (issue: string | null) => {
    if (issue && !issues.includes(issue)) issues.push(issue);
  };
  if (bank.collectPages) {
    for (const page of bank.collectPages) {
      const matching = tabResults
        .filter((entry) => urlOf(entry).includes(page.match))
        .sort((left, right) => categoryCount(right) - categoryCount(left));
      if (matching.length) {
        add(resultIssue(page.label, matching[0]!));
        continue;
      }
      const entry = opened.find((candidate) => candidate.page === page);
      if (!entry) add(`${page.label}: страница не открыта`);
      else if (entry.id == null) add(`${page.label}: не удалось открыть страницу в фоновой вкладке`);
      else if (entry.url && !entry.url.includes(page.match)) {
        add(`${page.label}: фоновая вкладка открыла ${shortUrl(entry.url)} вместо страницы категорий` +
          (isLoginUrl(entry.url) ? ' — требуется вход в банк' : ''));
      } else if (!entry.loaded) {
        add(`${page.label}: страница не загрузилась за ${Math.round(backgroundOptions.loadTimeoutMs / 1000)} с`);
      } else {
        add(`${page.label}: вкладка закрылась или не ответила`);
      }
    }
    return issues;
  }
  if (response?.categories.length) {
    const chosen = tabResults.find(({ result }) => result.kind === 'probe' && result.probe === response);
    if (chosen) add(resultIssue(tabLabel(bank, response.url), chosen));
    return issues;
  }
  for (const entry of tabResults) add(resultIssue(tabLabel(bank, urlOf(entry)), entry));
  return issues;
}

export const NO_CATEGORIES_MESSAGE = '«Собрать все» не нашёл категорий — причины ниже';

async function probeBankTabs(
  bank: BankDefinition,
  tabs: Tab[],
  mode: ProbeMode,
  opened: OpenedPage[] = [],
  backgroundOptions: BackgroundPageOptions = BACKGROUND_PAGE_OPTIONS,
): Promise<BankProbeOutcome> {
  const bankId = bank.id;
  const thorough = mode === 'thorough';
  const withIssues = <T extends BankProbeOutcome>(outcome: T, tabResults: TabResult[], response?: PageProbe): T =>
    thorough ? { ...outcome, issues: collectionIssues(bank, tabResults, opened, response, backgroundOptions) } : outcome;

  if (!tabs.length) {
    if (opened.some((entry) => entry.url && isLoginUrl(entry.url))) {
      return withIssues({ status: 'auth', probe: null, message: 'Требуется авторизация' }, []);
    }
    return withIssues({
      status: 'waiting',
      probe: null,
      message: bank.collectPages
        ? 'Вкладка банка не открыта — «Собрать все» откроет страницы категорий в фоне'
        : 'Вкладка банка не открыта',
    }, []);
  }

  const withId = tabs.filter((tab) => tab.id != null);
  const results = await Promise.all(withId.map((tab) => probeTab(tab, bankId, mode)));
  const tabResults = withId.map((tab, index) => ({ tab, result: results[index]! }));
  const probes = results.flatMap((result) => result.kind === 'probe' ? [result.probe] : []);
  // Banks whose categories span several pages are merged; otherwise the most
  // complete tab wins (other tabs may show a login or an unrelated page).
  const pageProbes = bank.collectPages
    ? probes.filter((probe) => bank.collectPages!.some((page) => probe.url.includes(page.match)) && probe.categories.length)
    : [];
  const response = pageProbes.length > 1
    ? mergeBankProbes(pageProbes, bank.preferredUrlParts)
    : bestProbe(probes, bank.preferredUrlParts);

  if (!response) {
    if (tabs.some(isAuthenticationTab)) {
      return withIssues({ status: 'auth', probe: null, message: 'Требуется авторизация' }, tabResults);
    }
    const failure = results.find((result) => result.kind === 'failed');
    const reason = failure?.kind === 'failed' ? failure.error : '';
    return withIssues({
      status: 'error',
      probe: null,
      message: failure?.kind === 'failed' && failure.noReceiver
        ? 'Расширение не подключилось к вкладке — обновите её'
        : `Страница банка не ответила${reason ? `: ${reason}` : ''}`,
    }, tabResults);
  }
  if (
    response.authenticationStatus === 'authentication_required' ||
    (response.categories.length === 0 && tabs.some(isAuthenticationTab))
  ) {
    return withIssues({ status: 'auth', probe: null, message: 'Требуется авторизация' }, tabResults);
  }
  if (response.categories.length === 0) {
    const selectionPage = probes.some((probe) => probe.capture?.selectionPage);
    // A multi-page bank (Ozon) read every page after the click; its empty
    // selection page is one of the reasons, not the explanation.
    if (selectionPage && !(thorough && bank.collectPages)) {
      return withIssues({ status: 'waiting', probe: null, message: SELECTION_PAGE_MESSAGE }, tabResults);
    }
    // After a click an empty result is a failure with reasons, not a silent wait.
    if (thorough) return withIssues({ status: 'error', probe: null, message: NO_CATEGORIES_MESSAGE }, tabResults);
    return {
      status: 'waiting',
      probe: null,
      message: bank.collectPages
        ? 'Ожидаю страницу категорий — «Собрать все» откроет нужные страницы в фоне'
        : 'Ожидаю страницу категорий',
    };
  }
  return withIssues({
    status: 'ready',
    probe: response,
    message: response.capture && !response.capture.stable
      ? 'Страница ещё догружалась — список может быть неполным, нажмите «Собрать все» ещё раз'
      : null,
  }, tabResults, response);
}
