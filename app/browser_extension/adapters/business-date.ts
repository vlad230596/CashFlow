/** Bank periods are calendar dates in Moscow, independent of browser timezone. */
export function moscowCalendarDate(instant: Date): { year: number; month: number; day: number } {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Moscow', year: 'numeric', month: 'numeric', day: 'numeric',
  }).formatToParts(instant);
  const number = (kind: string) => Number(parts.find(part => part.type === kind)!.value);
  return { year: number('year'), month: number('month'), day: number('day') };
}
