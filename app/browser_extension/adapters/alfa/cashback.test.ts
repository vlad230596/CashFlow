import { describe, expect, it } from 'vitest';
import { isAlfaMonthlySubtitle, isAlfaTaskBonus, parseAlfaCategoryTitle } from './cashback';

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

  it('does not treat a bare month label as a category', () => {
    expect(isAlfaMonthlySubtitle('В сентябре')).toBe(false);
  });
});

describe('isAlfaTaskBonus', () => {
  it('recognizes a disabled selection checkbox as a task reward', () => {
    const input = {
      disabled: true,
      getAttribute: () => null,
    } as unknown as HTMLInputElement;
    expect(isAlfaTaskBonus(input)).toBe(true);
  });

  it('keeps an enabled selection checkbox selectable', () => {
    const input = {
      disabled: false,
      getAttribute: () => null,
    } as unknown as HTMLInputElement;
    expect(isAlfaTaskBonus(input)).toBe(false);
  });
});
