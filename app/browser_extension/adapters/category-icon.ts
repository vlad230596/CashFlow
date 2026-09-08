import type { BankId, CashbackCategory } from './types';

const BANK_COLORS: Record<BankId, string> = {
  tbank: '#ffdd2d',
  yandex: '#ffcc00',
  alfa: '#ef3124',
  sber: '#21a038',
  ozon: '#005bff',
  vtb: '#00aaff',
};

function hashText(value: string): string {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

export function buildCategoryIconId(
  bankId: BankId,
  category: Pick<CashbackCategory, 'type' | 'name' | 'percentLabel'>,
): string {
  const identity = [
    bankId,
    category.type,
    category.percentLabel ?? '',
    category.name.replace(/\s+/g, ' ').trim().toLocaleLowerCase('ru'),
  ].join('|');
  return `${bankId}-${hashText(identity)}`;
}

function symbolForCategory(name: string): string {
  const value = name.toLocaleLowerCase('ru').replaceAll('ё', 'е');
  if (/красот|космет|парфюм|салон|спа|летуал|рив гош/.test(value)) return '✨';
  if (/дет|ребен|игруш|малыш/.test(value)) return '🧸';
  if (/книг|образован|обучен|школ|курс/.test(value)) return '📚';
  if (/кино|театр|развлеч/.test(value)) return '🎭';
  if (/хобби|творч|искусств/.test(value)) return '🎨';
  if (/подар|цвет/.test(value)) return '✿';
  if (/спорт|фитнес|активн/.test(value)) return '⚽';
  if (/путеше|отел|авиа|тревел/.test(value)) return '✈';
  if (/такси|каршер/.test(value)) return '🚕';
  if (/транспорт|метро|автобус/.test(value)) return '▰';
  if (/аптек|здоров|медицин/.test(value)) return '✚';
  if (/топлив|азс|заправ/.test(value)) return '⛽';
  if (/авто/.test(value)) return '◆';
  if (/дом|ремонт|мебел/.test(value)) return '⌂';
  if (/одеж|обув/.test(value)) return '👕';
  if (/животн|питом|зоотовар/.test(value)) return '●';
  if (/кафе|ресторан|фастфуд|кофе|еда/.test(value)) return '♨';
  if (/продукт|супермаркет|лавк/.test(value)) return '🛒';
  if (/электрон|техник|цифров/.test(value)) return '▣';
  if (/страхован|каско|осаго/.test(value)) return '◇';
  if (/все|покуп/.test(value)) return '∞';
  if (/музык/.test(value)) return '♪';
  return '◆';
}

export function buildFallbackCategoryIcon(bankId: BankId, name: string): string {
  const symbol = symbolForCategory(name);
  const foreground = bankId === 'tbank' || bankId === 'yandex' ? '#172033' : '#ffffff';
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96"><rect width="96" height="96" rx="24" fill="${BANK_COLORS[bankId]}"/><text x="48" y="57" text-anchor="middle" font-family="Segoe UI Emoji,Segoe UI Symbol,sans-serif" font-size="42" fill="${foreground}">${symbol}</text></svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

export function withCategoryIcon(
  bankId: BankId,
  category: CashbackCategory,
): CashbackCategory {
  return {
    ...category,
    iconId: buildCategoryIconId(bankId, category),
    iconUrl: category.iconUrl || buildFallbackCategoryIcon(bankId, category.name),
  };
}
