import { findBank } from '../banks/registry';
import type { BankId, PageProbe, ProbeMode } from './types';
import type { ProbeResponse } from './probe-runner';

/**
 * Side-panel side of category collection: talks to the bank tabs, survives
 * SPA/full navigations and missing content scripts, and never hangs.
 */

export type BankProbeOutcome =
  | { status: 'ready'; probe: PageProbe; message: string | null }
  | { status: 'auth' | 'waiting' | 'error'; probe: null; message: string };

type Tab = { id?: number; url?: string; title?: string; status?: string };

export type ProbeClientOptions = {
  /** Upper bound for one tab's answer. */
  timeoutMs: number;
  /** Retries for transient failures (navigation closed the channel). */
  retries: number;
  retryDelayMs: number;
};

export const PROBE_CLIENT_OPTIONS: Record<ProbeMode, ProbeClientOptions> = {
  passive: { timeoutMs: 12_000, retries: 1, retryDelayMs: 600 },
  thorough: { timeoutMs: 25_000, retries: 4, retryDelayMs: 900 },
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

export async function probeBank(bankId: BankId, mode: ProbeMode): Promise<BankProbeOutcome> {
  const bank = findBank(bankId);
  const tabs = (await browser.tabs.query({ url: bank.tabPatterns })) as Tab[];
  if (!tabs.length) return { status: 'waiting', probe: null, message: 'Вкладка банка не открыта' };

  const results = await Promise.all(tabs.filter((tab) => tab.id != null).map((tab) => probeTab(tab, bankId, mode)));
  const probes = results.flatMap((result) => result.kind === 'probe' ? [result.probe] : []);
  const response = bestProbe(probes, bank.preferredUrlParts);

  if (!response) {
    if (tabs.some(isAuthenticationTab)) return { status: 'auth', probe: null, message: 'Требуется авторизация' };
    const failure = results.find((result) => result.kind === 'failed');
    const reason = failure?.kind === 'failed' ? failure.error : '';
    return {
      status: 'error',
      probe: null,
      message: failure?.kind === 'failed' && failure.noReceiver
        ? 'Расширение не подключилось к вкладке — обновите её'
        : `Страница банка не ответила${reason ? `: ${reason}` : ''}`,
    };
  }
  if (
    response.authenticationStatus === 'authentication_required' ||
    (response.categories.length === 0 && tabs.some(isAuthenticationTab))
  ) {
    return { status: 'auth', probe: null, message: 'Требуется авторизация' };
  }
  if (response.categories.length === 0) {
    return { status: 'waiting', probe: null, message: 'Ожидаю страницу категорий' };
  }
  return {
    status: 'ready',
    probe: response,
    message: response.capture && !response.capture.stable
      ? 'Страница ещё догружалась — список может быть неполным, нажмите «Собрать все» ещё раз'
      : null,
  };
}
