import { describe, expect, it } from 'vitest';
import { parseYandexCashbackCardText, parseYandexPercent } from './cashback';

describe('parseYandexPercent', () => {
  it('parses a selected monthly cashback percentage', () => {
    expect(parseYandexPercent(' 3% ')).toEqual({
      percent: 3,
      percentLabel: '3%',
    });
  });

  it('preserves the up-to qualifier', () => {
    expect(parseYandexPercent('до 5%')).toEqual({
      percent: 5,
      percentLabel: 'до 5%',
    });
  });

  it('handles a non-percentage benefit', () => {
    expect(parseYandexPercent('Яндекс Плюс')).toEqual({
      percent: null,
      percentLabel: null,
    });
  });
});

describe('parseYandexCashbackCardText', () => {
  it('keeps the time limit and additional condition', () => {
    expect(
      parseYandexCashbackCardText(
        'Одежда и обувь\nНе суммируется с категориями\n7%\nещё 43 дня',
      ),
    ).toEqual({
      name: 'Одежда и обувь',
      percent: 7,
      percentLabel: '7%',
      subtitle: 'ещё 43 дня',
      description: 'Не суммируется с категориями',
      expiresInLabel: 'ещё 43 дня',
    });
  });
});
