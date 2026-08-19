import { describe, expect, it } from 'vitest';
import { parseVtbCategoryTitle } from './cashback';

describe('parseVtbCategoryTitle', () => {
  it('parses a VTB category title', () => {
    expect(parseVtbCategoryTitle('15% Авито Путешествия')).toEqual({
      name: 'Авито Путешествия',
      percent: 15,
      percentLabel: '15%',
    });
  });

  it('supports a decimal percentage', () => {
    expect(parseVtbCategoryTitle('1,5% Все покупки')).toEqual({
      name: 'Все покупки',
      percent: 1.5,
      percentLabel: '1,5%',
    });
  });

  it('does not parse a cashback limit', () => {
    expect(parseVtbCategoryTitle('Кешбэк до 500 ₽')).toBeNull();
  });
});
