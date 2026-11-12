import { buildPageProbe } from './page-probe';
import type { BankId, CashbackCategory, PageProbe, ProbeCapture, ProbeMode } from './types';

/**
 * Content-script side of category collection.
 *
 * Bank pages are SPAs: lists render after the script runs, arrive in chunks,
 * are virtualised, or appear only after a navigation click. A single
 * synchronous DOM read (the original design) returned whatever happened to be
 * rendered at that instant, so the user had to press "Собрать" repeatedly and
 * a later, smaller read could replace an earlier complete one.
 *
 * `captureCategories` instead polls the passive extractor until the result has
 * stayed identical for a quiet period (and the DOM stopped changing), merges
 * every read so rows that were rendered only briefly are not dropped, and
 * performs at most a few bounded "show more" and navigation steps.
 *
 * Automatic (passive) probes run every few seconds while the user may be
 * choosing categories in the same tab. They therefore only read and expand
 * in-page lists: navigation (`advance`) happens only after a user click
 * (thorough mode), and never on a page the adapter reports as a selection
 * page, where a navigation or reload would discard a half-made choice.
 */

export type ProbeRequest = { type: 'cashflow:probe-page'; mode?: ProbeMode };

export type ProbeSource = {
  bankId: BankId;
  /** Passive read of the current page. Must not click or navigate. */
  read(): CashbackCategory[] | Promise<CashbackCategory[]>;
  /**
   * One navigation step towards the category list (opening another route,
   * dialog or program card). Runs only in thorough mode and never while
   * `isSelectionPage()` is true. Receives everything collected so far and
   * returns true when it acted on the page.
   */
  advance?(collected: CashbackCategory[]): boolean;
  /**
   * In-page "show more" step that neither navigates nor changes any choice.
   * Allowed in both modes, but not on a selection page.
   */
  expand?(collected: CashbackCategory[]): boolean;
  /**
   * True on a page where the user picks categories (checkboxes, a selection
   * form). Collection then only reads: no navigation, clicks or detail sheets.
   */
  isSelectionPage?(): boolean;
  /** Detail enrichment (tooltips, sheets) once the list is stable. */
  enrich?(categories: CashbackCategory[], mode: ProbeMode): Promise<CashbackCategory[]>;
  /** Final adjustments to the probe (for example API-provided limits). */
  finish?(probe: PageProbe): PageProbe;
  /** Thorough probes walk the page's scroll range to render lazy rows. */
  scrollLazyContent?: boolean;
};

export type ProbeTiming = {
  /** Upper bound for waiting on the page. */
  timeoutMs: number;
  /** The result must stay unchanged (and the DOM quiet) this long. */
  quietMs: number;
  pollMs: number;
  /** Minimum delay between two advance() calls. */
  advanceEveryMs: number;
  maxAdvances: number;
};

export const PROBE_TIMING: Record<ProbeMode, ProbeTiming> = {
  // Automatic background probes run every few seconds; keep them short.
  passive: { timeoutMs: 3500, quietMs: 500, pollMs: 120, advanceEveryMs: 1500, maxAdvances: 2 },
  // A user click may wait for a navigation and a slow list.
  thorough: { timeoutMs: 10000, quietMs: 900, pollMs: 150, advanceEveryMs: 1500, maxAdvances: 4 },
};

export type ProbeEnvironment = {
  now(): number;
  sleep(ms: number): Promise<void>;
  /** Subscribes to DOM mutations; returns an unsubscribe function. */
  observe(onMutation: () => void): () => void;
};

export function browserProbeEnvironment(): ProbeEnvironment {
  return {
    now: () => Date.now(),
    sleep: (ms) => new Promise((resolve) => window.setTimeout(resolve, ms)),
    observe(onMutation) {
      if (typeof MutationObserver === 'undefined' || !document.body) return () => undefined;
      // Attribute changes are ignored: carousels and spinners animate attributes
      // forever, while new rows always change the child list or text.
      const observer = new MutationObserver(() => onMutation());
      observer.observe(document.body, { childList: true, subtree: true, characterData: true });
      return () => observer.disconnect();
    },
  };
}

const normalized = (value: string) => value.replace(/\s+/g, ' ').trim().toLocaleLowerCase('ru-RU').replaceAll('ё', 'е');

/** Identity of a category inside one bank result. */
export function categoryKey(category: Pick<CashbackCategory, 'type' | 'name' | 'percentLabel'>): string {
  return `${category.type}\u0000${normalized(category.name)}\u0000${category.percentLabel ?? ''}`;
}

function signature(categories: Iterable<CashbackCategory>): string {
  return [...categories]
    .map((category) => `${categoryKey(category)}\u0000${category.selected}\u0000${category.confirmed ?? ''}`)
    .sort()
    .join('\u0001');
}

export type CaptureResult = { categories: CashbackCategory[]; capture: ProbeCapture };

async function walkScrollRange(
  read: () => Promise<void>,
  environment: ProbeEnvironment,
  pollMs: number,
): Promise<void> {
  const scroller = typeof document === 'undefined' ? null : document.scrollingElement;
  if (!scroller || scroller.scrollHeight <= scroller.clientHeight + 4) return;
  const initialTop = scroller.scrollTop;
  const step = Math.max(300, Math.floor(scroller.clientHeight * 0.7));
  try {
    for (let top = 0, steps = 0; steps < 60; steps += 1) {
      scroller.scrollTo({ top, behavior: 'instant' as ScrollBehavior });
      window.dispatchEvent(new Event('scroll'));
      await environment.sleep(pollMs);
      await read();
      const bottom = scroller.scrollHeight - scroller.clientHeight;
      if (top >= bottom) break;
      top = Math.min(top + step, bottom);
    }
  } finally {
    scroller.scrollTo({ top: initialTop, behavior: 'instant' as ScrollBehavior });
  }
}

export async function captureCategories(
  source: ProbeSource,
  mode: ProbeMode,
  environment: ProbeEnvironment = browserProbeEnvironment(),
  timing: ProbeTiming = PROBE_TIMING[mode],
): Promise<CaptureResult> {
  const startedAt = environment.now();
  const collected = new Map<string, CashbackCategory>();
  let lastSignature = '';
  let lastChangeAt = startedAt;
  let lastMutationAt = startedAt;
  let lastAdvanceAt = Number.NEGATIVE_INFINITY;
  let advances = 0;
  let reads = 0;
  let selectionPage = false;
  const selectionPageNow = () => {
    let value = false;
    try { value = Boolean(source.isSelectionPage?.()); } catch { value = false; }
    if (value) selectionPage = true;
    return value;
  };
  const stopObserving = environment.observe(() => { lastMutationAt = environment.now(); });

  const readOnce = async () => {
    let categories: CashbackCategory[] = [];
    try {
      categories = await source.read();
    } catch {
      categories = [];
    }
    reads += 1;
    // Newer reads win for the same category (selection may change), but rows
    // that disappeared because of virtual scrolling or re-rendering are kept.
    for (const category of categories) collected.set(categoryKey(category), category);
    const next = signature(collected.values());
    if (next !== lastSignature) {
      lastSignature = next;
      lastChangeAt = environment.now();
    }
  };

  let stable = false;
  try {
    await readOnce();
    if (mode === 'thorough' && source.scrollLazyContent && collected.size) {
      await walkScrollRange(readOnce, environment, timing.pollMs);
    }
    for (;;) {
      const now = environment.now();
      const mayAct = advances < timing.maxAdvances &&
        now - lastAdvanceAt >= timing.advanceEveryMs && !selectionPageNow();
      // Navigation only after a user click; in-page expansion in both modes.
      const acted = mayAct && (
        (mode === 'thorough' && source.advance?.([...collected.values()]) === true) ||
        source.expand?.([...collected.values()]) === true
      );
      if (acted) {
        advances += 1;
        lastAdvanceAt = now;
        lastChangeAt = now;
      }
      const quietFor = now - lastChangeAt;
      const domQuietFor = now - lastMutationAt;
      if (collected.size && quietFor >= timing.quietMs && domQuietFor >= timing.quietMs) {
        stable = true;
        break;
      }
      if (now - startedAt >= timing.timeoutMs) {
        // Endless animations can keep the DOM busy; an unchanged result is
        // still a stable result.
        stable = collected.size > 0 && quietFor >= timing.quietMs;
        break;
      }
      await environment.sleep(timing.pollMs);
      await readOnce();
    }
  } finally {
    stopObserving();
  }

  return {
    categories: [...collected.values()],
    capture: {
      mode,
      stable,
      waitedMs: Math.round(environment.now() - startedAt),
      reads,
      advances,
      ...(selectionPage ? { selectionPage: true } : {}),
    },
  };
}

export async function runProbe(
  source: ProbeSource,
  mode: ProbeMode,
  environment?: ProbeEnvironment,
  timing?: ProbeTiming,
): Promise<PageProbe> {
  const { categories, capture } = await captureCategories(source, mode, environment, timing);
  let enriched = categories;
  // Detail sheets and tooltips are clicked open; leave a selection page alone.
  if (categories.length && source.enrich && !capture.selectionPage) {
    try {
      enriched = await source.enrich(categories, mode);
    } catch {
      // Descriptions are optional; never lose the list because of a tooltip.
      enriched = categories;
    }
  }
  const probe = { ...buildPageProbe(source.bankId, enriched), capture };
  return source.finish ? source.finish(probe) : probe;
}

/**
 * Single-flight wrapper: overlapping requests (several side panels, a manual
 * click during an automatic probe) share one capture instead of clicking and
 * scrolling the same page concurrently. A thorough request that arrives while
 * a passive capture is running waits for it and then runs its own capture.
 */
export function createProbeHandler(
  source: ProbeSource,
  environment?: ProbeEnvironment,
  timings: Record<ProbeMode, ProbeTiming> = PROBE_TIMING,
) {
  let current: { mode: ProbeMode; promise: Promise<PageProbe> } | null = null;
  const start = (mode: ProbeMode): Promise<PageProbe> => {
    const promise = runProbe(source, mode, environment, timings[mode]).finally(() => {
      if (current?.promise === promise) current = null;
    });
    current = { mode, promise };
    return promise;
  };
  return (mode: ProbeMode = 'passive'): Promise<PageProbe> => {
    if (!current) return start(mode);
    if (current.mode === 'thorough' || mode === 'passive') return current.promise;
    const previous = current.promise;
    const chained = previous.catch(() => undefined).then(() => start('thorough'));
    current = { mode: 'thorough', promise: chained };
    return chained;
  };
}

export type ProbeResponse = PageProbe | { error: string };

/**
 * Registers the probe listener once per page. `sendResponse` + `return true`
 * is used instead of returning a Promise because Chrome only recently started
 * honouring promise-returning onMessage listeners.
 */
export function registerProbeListener(source: ProbeSource): void {
  const flag = `__cashflowProbe_${source.bankId}`;
  const scope = globalThis as unknown as Record<string, unknown>;
  // Scripts re-injected by the side panel must not add a second listener.
  if (scope[flag]) return;
  scope[flag] = true;
  const handle = createProbeHandler(source);
  browser.runtime.onMessage.addListener((message: unknown, _sender, sendResponse) => {
    const request = message as ProbeRequest | undefined;
    if (request?.type !== 'cashflow:probe-page') return undefined;
    handle(request.mode === 'thorough' ? 'thorough' : 'passive').then(
      (probe) => sendResponse(probe satisfies ProbeResponse),
      (error: unknown) => sendResponse({ error: String(error) } satisfies ProbeResponse),
    );
    return true;
  });
}
