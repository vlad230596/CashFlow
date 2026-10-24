import { describe, expect, it } from 'vitest';
import { ageLabel, extendedFreshness } from './freshness';
import type { ExtendedBankResult, ExtendedOffer } from './types';

const now = new Date('2026-10-21T12:00:00Z');
const offer = (id: string) => ({ id, name: id }) as ExtendedOffer;
const result = (patch: Partial<ExtendedBankResult>): ExtendedBankResult => ({
  bankId: 'ozon', collectedAt: '2026-10-21T10:00:00Z', sourceUrls: [],
  offers: [offer('a'), offer('old')], previewCount: 1, reusedCount: 0,
  openedCount: 0, previewOnlyCount: 0, errors: [],
  runStatus: 'complete', catalogIds: ['a'], ...patch,
});

describe('extended offer freshness', () => {
  it('reports a missing collection', () => {
    expect(extendedFreshness(undefined, now).state).toBe('missing');
  });

  it('keeps only offers listed by the bank in a fresh run', () => {
    const value = extendedFreshness(result({}), now);
    expect(value.state === 'fresh' && value.offers.map((item) => item.id)).toEqual(['a']);
    expect(value.state === 'fresh' && value.age).toBe('2 ч назад');
  });

  it('treats a collection older than one day as stale', () => {
    expect(extendedFreshness(result({ collectedAt: '2026-10-20T11:59:00Z' }), now).state).toBe('stale');
    expect(extendedFreshness(result({ collectedAt: '2026-09-16T08:00:00Z' }), now).state).toBe('stale');
  });

  it('reports a failed run with its first error instead of offers', () => {
    expect(extendedFreshness(result({ runStatus: 'failed', errors: ['Нет связи'] }), now))
      .toMatchObject({ state: 'failed', age: '2 ч назад', error: 'Нет связи' });
  });

  it('separates an active run from an interrupted one', () => {
    const running = result({ runStatus: 'running' });
    expect(extendedFreshness(running, now, true)).toMatchObject({ run: 'running' });
    expect(extendedFreshness(running, now, false)).toMatchObject({ run: 'interrupted' });
  });

  it('keeps every offer of a legacy record without run metadata', () => {
    const legacy = result({ runStatus: undefined, catalogIds: undefined });
    const value = extendedFreshness(legacy, now);
    expect(value).toMatchObject({ run: 'unknown' });
    expect(value.state === 'fresh' && value.offers).toHaveLength(2);
  });

  it('formats ages', () => {
    expect(ageLabel(30_000)).toBe('только что');
    expect(ageLabel(5 * 60_000)).toBe('5 мин назад');
    expect(ageLabel(35 * 24 * 3_600_000)).toBe('35 дн назад');
  });
});
