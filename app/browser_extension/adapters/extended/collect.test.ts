import { afterEach, expect, it, vi } from 'vitest';
import { collectExtendedBank } from './collect';
import { extendedFreshness } from './freshness';
import type { ExtendedBankResult } from './types';

const route = 'https://bank.yandex.ru/webview-sdk/partners/cashback';

const previous: ExtendedBankResult = {
  bankId: 'yandex', collectedAt: '2026-11-11T07:00:00.000Z', sourceUrls: [route],
  offers: [{
    bankId: 'yandex', id: 'offer-1', name: 'Тестовый магазин', offerKind: 'cashback', percent: 10, rateLabel: '10%',
    startDate: null, endDate: null, expirationLabel: null, previewConditions: null, previewText: '10% Тестовый магазин',
    group: null, sourceUrl: route, detailUrl: null, iconUrl: null, artworkUrl: null, selected: null, canOpenSafely: false,
    type: 'partner_offer', description: null, conditions: 'Условия', steps: [], links: [], maxCashbackAmount: null,
    minPurchaseAmount: null, detailsStatus: 'complete', detailsError: null, previewFingerprint: 'x', detailCollectedAt: null,
  }],
  previewCount: 1, reusedCount: 0, openedCount: 1, previewOnlyCount: 0, errors: [], runStatus: 'complete', catalogIds: ['offer-1'],
};

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

it('keeps an earlier good collection when a retry finds an empty catalogue', async () => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-11-11T08:00:00.000Z'));
  const storage: Record<string, unknown> = { 'cashflowExtendedHistory:yandex': previous };
  const writes: unknown[] = [];
  vi.stubGlobal('browser', {
    storage: {
      local: {
        get: vi.fn(async (key: string) => ({ [key]: storage[key] })),
        set: vi.fn(async (values: Record<string, unknown>) => { writes.push(values); Object.assign(storage, values); }),
      },
    },
    tabs: {
      query: vi.fn(async () => [{ id: 3, url: route }]),
      get: vi.fn(async () => ({ id: 3, url: route, status: 'complete' })),
      update: vi.fn(async () => ({})),
      // The page answers, but its catalogue is empty (for example still loading).
      sendMessage: vi.fn(async (_tabId: number, message: { type: string }) =>
        message.type === 'cashflow:extended-ping' ? true : []),
    },
  });

  const run = collectExtendedBank('yandex');
  const outcome = expect(run).rejects.toThrow(/пуст/);
  await vi.runAllTimersAsync();
  await outcome;

  const stored = storage['cashflowExtendedHistory:yandex'] as ExtendedBankResult;
  expect(stored.offers.map((offer) => offer.id)).toEqual(['offer-1']);
  expect(stored.runStatus).toBe('complete');
  expect(stored.catalogIds).toEqual(['offer-1']);
  expect(stored.lastFailure?.error).toMatch(/пуст/);
  // No intermediate write replaced the record with an incomplete catalogue.
  expect(writes).toHaveLength(1);
  const freshness = extendedFreshness(stored, new Date('2026-11-11T08:01:00.000Z'));
  expect(freshness).toMatchObject({ state: 'fresh', run: 'complete' });
  expect(freshness.state === 'fresh' && freshness.offers).toHaveLength(1);
});
