import { expect, it } from 'vitest';
import { moscowCalendarDate } from './business-date';
import { showsCurrentCashbackMonth } from './monthly-confirmation';
it('uses the Moscow month around UTC midnight regardless of browser timezone', () => {
  const instant = new Date('2026-09-30T21:30:00Z');
  expect(moscowCalendarDate(instant)).toEqual({ year: 2026, month: 10, day: 1 });
  expect(showsCurrentCashbackMonth('Категории в октябре', instant)).toBe(true);
  expect(showsCurrentCashbackMonth('Категории в сентябре', instant)).toBe(false);
});
