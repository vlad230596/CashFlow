import { describe, expect, it } from 'vitest';
import { parseOzonCategoryTitle } from './cashback';

describe('parseOzonCategoryTitle', () => {
  it('parses a monthly cashback category', () => {
    expect(parseOzonCategoryTitle('7% Яндекс Лавка')).toEqual({
      name: 'Яндекс Лавка',
      percent: 7,
      percentLabel: '7%',
    });
  });

  it('supports a decimal percentage', () => {
    expect(parseOzonCategoryTitle('1,5% Все покупки')).toEqual({
      name: 'Все покупки',
      percent: 1.5,
      percentLabel: '1,5%',
    });
  });

  it('does not parse partner promotion labels', () => {
    expect(parseOzonCategoryTitle('Кешбэк 30%')).toBeNull();
  });
});
