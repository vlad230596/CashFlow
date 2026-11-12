import { moscowCalendarDate } from './business-date';
import { categoryKey } from './probe-runner';
import { combineCategory } from './category-merge';
import type { BankProbeOutcome } from './probe-client';
import type { BankId, CashbackCategory, CashbackImportBankResult, CashbackImportDocument, CollectionStatus, PageProbe } from './types';

/**
 * Accumulated category results in the side panel.
 *
 * Previously every probe (including the automatic one every 5 s) replaced the
 * bank's result. A probe that ran while the page was re-rendering, after the
 * extended-offer collector navigated the tab elsewhere, or after the tab moved
 * to a sign-in page wiped categories collected seconds earlier, and the JSON
 * export then lacked them. Results are now merged and kept until the month
 * changes or the user clears them.
 */

export type BankView = {
  /** `ready` whenever exportable categories exist. */
  status: CollectionStatus;
  result: CashbackImportBankResult | null;
  message: string | null;
  /** Outcome of the latest probe, which may differ from `status`. */
  liveStatus?: CollectionStatus;
  /** Categories kept from earlier probes that the latest probe did not show. */
  retainedCount?: number;
};

export const emptyBankView = (): BankView => ({ status: 'waiting', result: null, message: null });

function sameMoscowMonth(left: Date, right: Date): boolean {
  const a = moscowCalendarDate(left);
  const b = moscowCalendarDate(right);
  return a.year === b.year && a.month === b.month;
}

function timeLabel(iso: string | null): string {
  if (!iso) return '';
  const date = new Date(iso);
  return Number.isNaN(date.getTime()) ? '' : date.toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
}

/**
 * Union of category lists. For categories present in both, `next` decides the
 * selection state, while details it lacks (a cap or a description read from a
 * detail sheet earlier) are kept from `previous`.
 */
export function mergeCategories(previous: CashbackCategory[], next: CashbackCategory[]): {
  categories: CashbackCategory[];
  retained: number;
} {
  const merged = new Map<string, CashbackCategory>();
  for (const category of next) merged.set(categoryKey(category), category);
  let retained = 0;
  for (const category of previous) {
    const key = categoryKey(category);
    const current = merged.get(key);
    if (current) {
      merged.set(key, combineCategory(current, category));
      continue;
    }
    merged.set(key, category);
    retained += 1;
  }
  return { categories: [...merged.values()], retained };
}

function resultFromProbe(bankName: string, probe: PageProbe, collectedAt: string): CashbackImportBankResult {
  const { capture: _capture, ...rest } = probe;
  return { ...rest, bankName, collectionStatus: 'ready', collectedAt, message: null };
}

export function mergeResult(
  previous: CashbackImportBankResult | null,
  probe: PageProbe,
  bankName: string,
  now: Date,
): { result: CashbackImportBankResult; retained: number } {
  const fresh = resultFromProbe(bankName, probe, now.toISOString());
  const previousAt = previous?.collectedAt ? new Date(previous.collectedAt) : null;
  if (!previous || !previousAt || !sameMoscowMonth(previousAt, now)) return { result: fresh, retained: 0 };

  const { categories, retained } = mergeCategories(previous.categories, fresh.categories);
  const standard = categories.filter((category) => category.type === 'standard');
  return {
    retained,
    result: {
      ...fresh,
      categories,
      selection: {
        isLocked: fresh.selection.isLocked ?? previous.selection.isLocked,
        selectedCount: standard.filter((category) => category.selected).length,
        visibleCount: standard.length,
        maxSelectable: fresh.selection.maxSelectable ?? previous.selection.maxSelectable,
        totalOptions: Math.max(fresh.selection.totalOptions ?? 0, previous.selection.totalOptions ?? 0, standard.length) || null,
        groups: [...new Set([...fresh.selection.groups, ...previous.selection.groups])],
      },
    },
  };
}

/** Applies one probe outcome without ever discarding exportable categories. */
export function applyOutcome(
  previous: BankView | undefined,
  outcome: BankProbeOutcome,
  bankName: string,
  now: Date,
): BankView {
  if (outcome.status === 'ready') {
    const { result, retained } = mergeResult(previous?.result ?? null, outcome.probe, bankName, now);
    return { status: 'ready', liveStatus: 'ready', result, message: outcome.message, retainedCount: retained };
  }
  if (previous?.result) {
    const kept = previous.result.collectedAt;
    return {
      ...previous,
      status: 'ready',
      liveStatus: outcome.status,
      message: `Сохранён сбор${kept ? ` от ${timeLabel(kept)}` : ''}. Сейчас: ${outcome.message}`,
    };
  }
  return { status: outcome.status, liveStatus: outcome.status, result: null, message: outcome.message };
}

export const COLLECTED_STORAGE_KEY = 'cashflowCollectedCategories';

export type StoredCollection = {
  schemaVersion: 1;
  savedAt: string;
  banks: Partial<Record<BankId, CashbackImportBankResult>>;
};

export function serializeViews(views: Partial<Record<BankId, BankView>>, now: Date): StoredCollection {
  const banks: Partial<Record<BankId, CashbackImportBankResult>> = {};
  for (const [id, view] of Object.entries(views) as Array<[BankId, BankView | undefined]>) {
    if (view?.result?.categories.length) banks[id] = view.result;
  }
  return { schemaVersion: 1, savedAt: now.toISOString(), banks };
}

export const RESTORE_MAX_AGE_MS = 24 * 60 * 60 * 1000;

/** Restores results from an earlier panel session (same Moscow month, last 24 h). */
export function restoreViews(stored: unknown, bankIds: BankId[], now: Date): Partial<Record<BankId, BankView>> {
  if (!stored || typeof stored !== 'object') return {};
  const value = stored as Partial<StoredCollection>;
  if (value.schemaVersion !== 1 || !value.banks || typeof value.banks !== 'object') return {};
  const views: Partial<Record<BankId, BankView>> = {};
  for (const id of bankIds) {
    const result = value.banks[id];
    const collectedAt = result?.collectedAt ? new Date(result.collectedAt) : null;
    if (
      !result || result.bankId !== id || !Array.isArray(result.categories) || !result.categories.length ||
      !collectedAt || Number.isNaN(collectedAt.getTime()) || !sameMoscowMonth(collectedAt, now) ||
      collectedAt.getTime() > now.getTime() + 60_000 ||
      now.getTime() - collectedAt.getTime() > RESTORE_MAX_AGE_MS
    ) continue;
    views[id] = {
      status: 'ready',
      liveStatus: 'waiting',
      result,
      message: `Восстановлен сбор от ${collectedAt.toLocaleString('ru-RU')}`,
    };
  }
  return views;
}

/** Banks whose categories would be skipped by the backend import. */
export function exportGaps(banks: CashbackImportBankResult[]): string[] {
  return banks
    .filter((bank) => bank.authenticationStatus !== 'authenticated' || !bank.categories.length)
    .map((bank) => bank.bankName);
}

export type BankExtras = Pick<CashbackImportBankResult, 'extendedOffers' | 'extendedSummary'>;

/** The document handed to the CashFlow app (`POST /api/cashback/import`). */
export function buildImportDocument(
  bankIds: BankId[],
  views: Partial<Record<BankId, BankView>>,
  bankName: (id: BankId) => string,
  extras: Partial<Record<BankId, BankExtras>> = {},
  now = new Date(),
): CashbackImportDocument {
  return {
    schemaVersion: 1,
    generatedAt: now.toISOString(),
    requestedBanks: bankIds,
    banks: bankIds.map((id): CashbackImportBankResult => {
      const view = views[id] ?? emptyBankView();
      const base: CashbackImportBankResult = view.result ?? {
        bankId: id,
        bankName: bankName(id),
        collectionStatus: view.status,
        collectedAt: null,
        title: null,
        url: null,
        readyState: null,
        authenticationStatus: view.status === 'auth' ? 'authentication_required' : 'unknown',
        selection: {
          isLocked: null, selectedCount: 0, visibleCount: 0, maxSelectable: null, totalOptions: null, groups: [],
        },
        categories: [],
        message: view.message,
      };
      const extra = extras[id];
      return extra ? { ...base, ...extra } : base;
    }),
  };
}

/** JSON written to the export file; icon URLs are exported separately as a ZIP. */
export function serializeImportDocument(document: CashbackImportDocument, now = new Date()): string {
  return JSON.stringify({
    ...document,
    generatedAt: now.toISOString(),
    banks: document.banks.map((bank) => ({
      ...bank,
      categories: bank.categories.map(({ iconUrl: _iconUrl, ...category }) => category),
    })),
  }, null, 2);
}
