import { describe, expect, it } from 'vitest';
import { createOffer, limitsFromConditions, previewFingerprint, reuseOffer, uniquePreviews } from './core';
import type { OfferPreview } from './types';

const preview: OfferPreview = {
  bankId: 'ozon', id: 'merchant-1', name: 'Магазин', offerKind: 'cashback', percent: 10,
  rateLabel: '10%', startDate: '2026-09-01', endDate: '2026-09-30',
  expirationLabel: 'До 30 сентября', previewConditions: 'От 500 ₽',
  previewText: '10% Магазин От 500 ₽', group: 'Покупки',
  sourceUrl: 'https://finance.ozon.ru/lk/promotions', detailUrl: null,
  iconUrl: 'https://example.com/icon.png', artworkUrl: null,
  selected: true, canOpenSafely: true,
};

describe('extended offer history', () => {
  it('reuses complete detail for an identical preview', () => {
    const saved = createOffer(preview, {
      description: 'Описание', conditions: 'Полные условия', steps: ['Оплатить'],
      links: [], maxCashbackAmount: 1000, minPurchaseAmount: 500,
    }, 'complete');
    expect(reuseOffer({ ...preview }, saved)?.conditions).toBe('Полные условия');
    expect(reuseOffer({ ...preview, endDate: '2026-10-31' }, saved)).toBeNull();
    expect(reuseOffer({ ...preview, previewConditions: 'От 700 ₽' }, saved)).toBeNull();
    expect(reuseOffer({ ...preview, iconUrl: null }, saved)).toBeNull();
  });

  it('never treats preview-only or failed detail as complete history', () => {
    expect(reuseOffer(preview, createOffer(preview, null, 'preview_only'))).toBeNull();
    expect(reuseOffer(preview, createOffer(preview, null, 'error', 'failed'))).toBeNull();
  });

  it('keeps one offer across categories and includes category membership in the fingerprint', () => {
    const offers = uniquePreviews([preview, { ...preview, group: 'Маркетплейсы' }]);
    expect(offers).toHaveLength(1);
    expect(offers[0]?.group).toBe('Маркетплейсы, Покупки');
    expect(previewFingerprint(offers[0]!)).not.toBe(previewFingerprint(preview));
  });

  it('extracts explicit monetary limits without treating an arbitrary price as a limit', () => {
    expect(limitsFromConditions('Покупка от 500 ₽. Максимальный кешбэк 2 000 ₽.')).toEqual({
      minPurchaseAmount: 500, maxCashbackAmount: 2000,
    });
    expect(limitsFromConditions('Товар стоит 500 ₽')).toEqual({
      minPurchaseAmount: null, maxCashbackAmount: null,
    });
  });
});
