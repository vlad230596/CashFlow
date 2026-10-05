import { describe, expect, it, vi, afterEach } from 'vitest';
import { isOzonSavedCategorySummary, parseOzonCategoryTitle } from './cashback';

describe('saved Ozon category summary', () => {
  afterEach(() => vi.useRealTimers());

  it('confirms the current month summary on the saved cashback page', () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2026, 9, 5));
    expect(isOzonSavedCategorySummary('Категории в октябре', '/lk/cashback', false)).toBe(true);
  });

  it.each([
    ['Категории в сентябре', '/lk/cashback', false],
    ['Категории в ноябре', '/lk/cashback', false],
    ['Категории в октябре', '/lk/favorite-categories-v3', false],
    ['Категории в октябре', '/lk/cashback', true],
    [null, '/lk/cashback', false],
  ])('does not confirm stale, future, or editable categories (%s)', (heading, path, controls) => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2026, 9, 5));
    expect(isOzonSavedCategorySummary(heading, path, controls)).toBe(false);
  });
});

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
