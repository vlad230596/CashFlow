import { describe, expect, it } from 'vitest';
import { isAlfaMonthlySubtitle, parseAlfaCategoryTitle } from './cashback';

describe('parseAlfaCategoryTitle', () => {
  it('parses a chosen category', () => {
    expect(parseAlfaCategoryTitle('5% Рестораны')).toEqual({
      name: 'Рестораны',
      percent: 5,
      percentLabel: '5%',
    });
  });

  it('preserves the month in a stackable category title', () => {
    expect(parseAlfaCategoryTitle('3% Аптеки в августе')?.name).toBe('Аптеки в августе');
  });

  it('recognizes a Russian monthly subtitle', () => {
    expect(isAlfaMonthlySubtitle('Аптеки в августе')).toBe(true);
  });
});
