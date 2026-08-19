import type { BankId } from '../adapters/types';

export type BankDefinition = {
  id: BankId;
  name: string;
  startUrl: string;
  tabPatterns: string[];
  preferredUrlParts: string[];
};

export const BANKS: BankDefinition[] = [
  {
    id: 'tbank',
    name: 'Т-Банк',
    startUrl: 'https://www.tbank.ru/mybank/bonuses/',
    tabPatterns: ['https://www.tbank.ru/*', 'https://id.tbank.ru/*'],
    preferredUrlParts: ['/mybank/bonuses'],
  },
  {
    id: 'yandex',
    name: 'Яндекс Пэй',
    startUrl:
      'https://sp.yandex.ru/cashback/current?utm_source=cashflow&utm_medium=extension',
    tabPatterns: ['https://bank.yandex.ru/*', 'https://sp.yandex.ru/*'],
    preferredUrlParts: ['/cashback/current'],
  },
  {
    id: 'alfa',
    name: 'Альфа-Банк',
    startUrl: 'https://web.alfabank.ru/marketplace/?loyaltyType=104',
    tabPatterns: ['https://web.alfabank.ru/*', 'https://private.auth.alfabank.ru/*'],
    preferredUrlParts: ['/marketplace/?loyaltyType=104', '/marketplace/'],
  },
  {
    id: 'sber',
    name: 'СберБанк',
    startUrl:
      'https://online.sberbank.ru/CSAFront/index.do#/app/loyalty/main/categories/select',
    tabPatterns: ['https://online.sberbank.ru/*'],
    preferredUrlParts: ['/loyalty/main/categories/select', '/loyalty/main/categories'],
  },
  {
    id: 'ozon',
    name: 'Ozon Банк',
    startUrl: 'https://finance.ozon.ru/lk/cashback',
    tabPatterns: ['https://finance.ozon.ru/*'],
    preferredUrlParts: ['/lk/cashback', '/lk/bonus'],
  },
  {
    id: 'vtb',
    name: 'ВТБ',
    startUrl: 'https://online.sbpvtb.ru/bonus/categories',
    tabPatterns: ['https://online.sbpvtb.ru/*'],
    preferredUrlParts: ['/bonus/categories', '/bonus'],
  },
];

export const DEFAULT_BANK_IDS = BANKS.map((bank) => bank.id);

export function findBank(id: BankId): BankDefinition {
  return BANKS.find((bank) => bank.id === id)!;
}
