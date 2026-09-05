import { describe, expect, it } from 'vitest';
import {
  extractTbankCashbackFromBonusesResponse,
  parseCashbackCategoryTitle,
} from './cashback';

describe('parseCashbackCategoryTitle', () => {
  it('separates the percentage from the category name', () => {
    expect(parseCashbackCategoryTitle('15% Страхование частных домов')).toEqual({
      name: 'Страхование частных домов',
      percent: 15,
      percentLabel: '15%',
    });
  });

  it('keeps an unknown title without inventing a percentage', () => {
    expect(parseCashbackCategoryTitle('Спецпредложение')).toEqual({
      name: 'Спецпредложение',
      percent: null,
      percentLabel: null,
    });
  });
});

describe('extractTbankCashbackFromBonusesResponse', () => {
  it('chooses the monthly group with active categories and preserves API details', () => {
    const result = extractTbankCashbackFromBonusesResponse({
      payload: {
        data: [
          {
            serviceType: 'regularEssences',
            data: {
              availableEssenceCount: 1,
              essences: [{ name: 'Дополнительная категория', percent: 10, isActive: false }],
            },
          },
          {
            serviceType: 'regularEssences',
            data: {
              availableEssenceCount: 0,
              essences: [
                {
                  name: 'Все покупки',
                  percent: 1,
                  isActive: true,
                  description: 'Описание',
                  logo: 'https://example.test/icon.png',
                  baseColor: '725DD6',
                },
                { name: 'Аптеки', percent: 5, isActive: false, mccCodes: ['5912'] },
              ],
            },
          },
        ],
      },
    });

    expect(result).toMatchObject({ maxSelectable: 1, totalOptions: 2 });
    expect(result?.categories[0]).toMatchObject({
      name: 'Все покупки',
      selected: true,
      description: 'Описание',
      iconUrl: 'https://example.test/icon.png',
      iconBackgroundColor: '#725DD6',
    });
    expect(result?.categories[1]?.subtitle).toBe('MCC: 5912');
  });

  it('chooses the full monthly group when a promotional group comes first', () => {
    const result = extractTbankCashbackFromBonusesResponse({
      payload: {
        data: [
          {
            serviceType: 'regularEssences',
            data: {
              availableEssenceCount: 1,
              essences: [
                { name: 'Подписка партнёра', percent: 50, isActive: false },
                { name: 'Игровой бонус', percent: 100, isActive: false },
              ],
            },
          },
          {
            serviceType: 'regularEssences',
            data: {
              availableEssenceCount: 4,
              essences: [
                { name: 'Все покупки', percent: 1, isActive: false },
                { name: 'Аптеки', percent: 5, isActive: false },
                { name: 'Такси', percent: 5, isActive: false },
              ],
            },
          },
        ],
      },
    });

    expect(result).toMatchObject({ maxSelectable: 4, totalOptions: 3 });
    expect(result?.categories.map((category) => category.name)).toEqual([
      'Все покупки',
      'Аптеки',
      'Такси',
    ]);
  });
});
