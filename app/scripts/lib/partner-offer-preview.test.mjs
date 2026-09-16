import test from 'node:test';
import assert from 'node:assert/strict';
import { offerMetadata } from './partner-offer-preview.mjs';

test('retains Ozon validity, monetary maximum and exclusions', () => {
  const metadata = offerMetadata({
    expirationLabel: 'До 30 сентября',
    conditions: 'Максимальная сумма кешбэка\n\n400 рублей\n\nКэшбэк не начисляется за покупки подарочных сертификатов',
  }, {});
  assert.equal(metadata.validityLabel, 'До 30 сентября');
  assert.deepEqual(metadata.limits, ['Максимальная сумма кешбэка: 400 рублей']);
  assert.ok(metadata.requirements.some(value => value.includes('подарочных сертификатов')));
});

test('keeps both Sber bonus limits and marks older missing conditions', () => {
  const metadata = offerMetadata({ details: { text: '' } }, { collectedAt: '2026-09-16' }, [{
    bank: { collectedAt: '2026-09-13' },
    raw: { details: { fullConditions: 'Максимум 1000 бонусов за одну покупку и 5000 бонусов за покупки в месяц' } },
  }]);
  assert.deepEqual(metadata.limits, ['Максимум 1000 бонусов за одну покупку и 5000 бонусов за покупки в месяц']);
  assert.equal(metadata.conditionsFromHistory, true);
  assert.equal(metadata.conditionsCollectedAt, '2026-09-13');
  assert.equal(metadata.validityLabel, null);
});

test('preserves a date range and prioritizes new customer eligibility', () => {
  const metadata = offerMetadata({
    endDate: '30.09.2026',
    details: { conditions: ['Срок действия\n26.08.2026 - 30.09.2026', 'Оплатите любой картой банка', 'Только для новых клиентов. На первую покупку от 500 ₽.'], terms: 'Максимальный кэшбэк — 3000 ₽' },
  }, {});
  assert.equal(metadata.validityLabel, '26.08.2026 - 30.09.2026');
  assert.ok(metadata.requirements[0].includes('новых клиентов'));
  assert.ok(metadata.conditions.includes('от 500 ₽'));
});

test('does not infer unlimited cashback or use older conditions over current ones', () => {
  const metadata = offerMetadata({ conditions: 'Только для новых клиентов' }, {}, [{ raw: { conditions: 'Максимум — 1000 ₽' }, bank: {} }]);
  assert.deepEqual(metadata.limits, []);
  assert.equal(metadata.conditionsFromHistory, false);
});
