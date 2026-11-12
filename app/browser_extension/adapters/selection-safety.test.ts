// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { runProbe, type ProbeSource, type ProbeTiming } from './probe-runner';
import { isCategorySelectionPage } from './selection-page';
import type { CashbackCategory } from './types';

/*
 * The owner was choosing November categories in a bank tab while the side
 * panel's automatic collection (every 5 s) navigated that tab and threw the
 * half-made choice away. Automatic probes may only read; a clicked probe may
 * navigate, but never away from a category-selection page.
 */

const FAST: ProbeTiming = { timeoutMs: 600, quietMs: 60, pollMs: 15, advanceEveryMs: 0, maxAdvances: 3 };

const category = (name: string): CashbackCategory => ({
  type: 'standard', name, percent: 5, percentLabel: '5%', subtitle: null, description: null,
  iconUrl: null, iconBackgroundColor: null, selected: true, group: null, expiresInLabel: null,
});

afterEach(() => vi.restoreAllMocks());

describe('isCategorySelectionPage', () => {
  it.each([
    ['tbank', 'https://www.tbank.ru/mybank/bonuses/high-cashback/offer/42/', true],
    ['tbank', 'https://www.tbank.ru/mybank/bonuses/', false],
    ['sber', 'https://online.sberbank.ru/app/loyalty/main/categories/select', true],
    ['sber', 'https://online.sberbank.ru/CSAFront/index.do#/app/loyalty/main/categories/select', true],
    ['sber', 'https://online.sberbank.ru/app/loyalty/main/categories', false],
    ['vtb', 'https://online.sbpvtb.ru/bonus/categories', true],
    ['vtb', 'https://online.sbpvtb.ru/bonus/categories/months', false],
    ['ozon', 'https://finance.ozon.ru/lk/favorite-categories-v3?type=current&fromHome=true', true],
    ['ozon', 'https://finance.ozon.ru/lk/cashback', false],
  ] as const)('%s %s → %s', (bankId, url, expected) => {
    document.body.innerHTML = '';
    expect(isCategorySelectionPage(bankId, url, document)).toBe(expected);
  });

  it('recognises the Alfa choice list by its checkboxes', () => {
    document.body.innerHTML = '<input type="checkbox" data-test-id="checkbox-select-cashback-1">';
    expect(isCategorySelectionPage('alfa', 'https://web.alfabank.ru/marketplace/?loyaltyType=104', document)).toBe(true);
    document.body.innerHTML = '<div data-test-id="chosen-category-item"></div>';
    expect(isCategorySelectionPage('alfa', 'https://web.alfabank.ru/marketplace/?loyaltyType=104', document)).toBe(false);
  });
});

describe('probe actions', () => {
  function source(overrides: Partial<ProbeSource> = {}) {
    const advance = vi.fn(() => true);
    const expand = vi.fn(() => false);
    const enrich = vi.fn(async (categories: CashbackCategory[]) => categories);
    return {
      advance, expand, enrich,
      source: { bankId: 'tbank' as const, read: () => [], advance, expand, enrich, ...overrides } satisfies ProbeSource,
    };
  }

  it('never navigates during an automatic (passive) probe', async () => {
    const { source: probeSource, advance, expand } = source();
    const probe = await runProbe(probeSource, 'passive', undefined, FAST);
    expect(advance).not.toHaveBeenCalled();
    expect(expand).toHaveBeenCalled();
    expect(probe.capture?.advances).toBe(0);
  });

  it('navigates only after a click (thorough probe) on an ordinary page', async () => {
    const { source: probeSource, advance } = source();
    await runProbe(probeSource, 'thorough', undefined, FAST);
    expect(advance).toHaveBeenCalled();
  });

  it('only reads a selection page, even after a click', async () => {
    const { source: probeSource, advance, expand, enrich } = source({
      read: () => [category('Аптеки')],
      isSelectionPage: () => true,
    });
    const probe = await runProbe(probeSource, 'thorough', undefined, FAST);
    expect(advance).not.toHaveBeenCalled();
    expect(expand).not.toHaveBeenCalled();
    expect(enrich).not.toHaveBeenCalled();
    expect(probe.capture?.selectionPage).toBe(true);
    expect(probe.categories.map((item) => item.name)).toEqual(['Аптеки']);
  });
});
