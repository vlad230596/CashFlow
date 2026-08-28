import { describe, expect, it } from 'vitest';
import { selectTbankMonthlyCashbackControl, selectTbankMonthlyCashbackUrl } from './navigation';

describe('selectTbankMonthlyCashbackUrl', () => {
  it('ignores partner offers and chooses the monthly category selector', () => {
    expect(selectTbankMonthlyCashbackUrl([
      { href: 'https://www.tbank.ru/mybank/bonuses/partners/', text: 'Предложения партнёров' },
      { href: 'https://www.tbank.ru/mybank/bonuses/high-cashback/offer/abc/', text: 'Категории повышенного кэшбэка' },
    ])).toBe('https://www.tbank.ru/mybank/bonuses/high-cashback/offer/abc/');
  });

  it('prefers the already active monthly cashback card', () => {
    expect(selectTbankMonthlyCashbackControl([
      { text: 'Повышенный кэшбэк на август Выбрать', id: 'available' },
      { text: 'Повышенный кэшбэк в августе', id: 'active' },
    ])?.id).toBe('active');
  });
});
