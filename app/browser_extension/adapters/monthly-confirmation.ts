const monthNames = [
  'январ(?:ь|е)', 'феврал(?:ь|е)', 'март(?:е)?', 'апрел(?:ь|е)', 'ма(?:й|е)', 'июн(?:ь|е)',
  'июл(?:ь|е)', 'август(?:е)?', 'сентябр(?:ь|е)', 'октябр(?:ь|е)', 'ноябр(?:ь|е)', 'декабр(?:ь|е)',
];

export function showsCurrentCashbackMonth(text: string, now = new Date()): boolean {
  return new RegExp(`(?:^|\\s)в\\s+${monthNames[now.getMonth()]}(?:\\s|$)`, 'i')
    .test(text.replace(/\s+/g, ' ').trim());
}
