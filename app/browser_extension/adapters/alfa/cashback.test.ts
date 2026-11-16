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

  it('parses the percent and name from separate Alfa category elements', () => {
    expect(parseAlfaCategoryTitle('10%', 'Аскона')).toEqual({
      name: 'Аскона', percent: 10, percentLabel: '10%',
    });
  });

  it('preserves the month in a stackable category title', () => {
    expect(parseAlfaCategoryTitle('3% Аптеки в августе')?.name).toBe('Аптеки в августе');
  });

  it('folds Latin lookalikes that Alfa mixes into Russian names', () => {
    expect(parseAlfaCategoryTitle('5%', 'Kниги')?.name).toBe('Книги');
    expect(parseAlfaCategoryTitle('5% Ювелирные издeлия')?.name).toBe('Ювелирные изделия');
    expect(parseAlfaCategoryTitle('2% Кафе и pестораны')?.name).toBe('Кафе и рестораны');
    expect(parseAlfaCategoryTitle('7% Фастфуд (Alfa Pay)')?.name).toBe('Фастфуд (Alfa Pay)');
    expect(parseAlfaCategoryTitle('15% Zolla')?.name).toBe('Zolla');
  });

  it('recognizes a monthly subtitle written with Latin lookalikes', () => {
    expect(isAlfaMonthlySubtitle('Kниги в нoябре')).toBe(true);
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
