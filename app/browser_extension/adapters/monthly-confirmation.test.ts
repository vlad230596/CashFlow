import { describe, expect, it } from 'vitest';
import { showsCurrentCashbackMonth } from './monthly-confirmation';

describe('saved cashback period', () => {
  it('accepts a saved current-month heading with bank spacing', () => {
    expect(showsCurrentCashbackMonth('Ваши категории в\u00a0сентябре', new Date(2026, 8, 16))).toBe(true);
  });
  it('rejects previous and next months', () => {
    const now = new Date(2026, 8, 16);
    expect(showsCurrentCashbackMonth('Мои категории В августе', now)).toBe(false);
    expect(showsCurrentCashbackMonth('Ваши категории в октябре', now)).toBe(false);
  });
  it('does not confuse March with May', () => {
    expect(showsCurrentCashbackMonth('Категории в марте', new Date(2026, 4, 1))).toBe(false);
    expect(showsCurrentCashbackMonth('Категории в мае', new Date(2026, 4, 1))).toBe(true);
  });
});
