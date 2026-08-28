import { describe, expect, it } from 'vitest';
import { parseSberCategoryTitle } from './cashback';

describe('parseSberCategoryTitle', () => {
  it('separates the percentage from the category name', () => {
    expect(parseSberCategoryTitle('10% Спорт и фитнес')).toEqual({
      name: 'Спорт и фитнес',
      percent: 10,
      percentLabel: '10%',
    });
  });

  it('supports a decimal percentage with a comma', () => {
    expect(parseSberCategoryTitle('1,5% На все покупки')).toEqual({
      name: 'На все покупки',
      percent: 1.5,
      percentLabel: '1,5%',
    });
  });

  it('does not turn unrelated partner offers into categories', () => {
    expect(parseSberCategoryTitle('Кешбэк 15% на Афише')).toBeNull();
  });
});
