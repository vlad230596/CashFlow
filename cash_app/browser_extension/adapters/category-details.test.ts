import { describe, expect, it } from 'vitest';
import {
  cleanVtbDescription,
  enrichCashbackCategory,
  extractCashbackAmounts,
} from './category-details';
import type { CashbackCategory } from './types';

const category: CashbackCategory = {
  type: 'standard',
  name: 'zolla',
  percent: 20,
  percentLabel: '20%',
  subtitle: 'При покупке от 5 000 ₽ онлайн и в розничных магазинах',
  description:
    'Кешбэк до 2 000 рублей\nMCC: 5691\nМСС — это код вида деятельности продавца. По нему банк определяет категорию покупки для расчета кешбэка.\nПри оплате по СБП кешбэк не начисляется',
  iconUrl: null,
  iconBackgroundColor: null,
  selected: false,
  group: null,
  expiresInLabel: null,
};

describe('category details', () => {
  it('extracts maximum cashback and minimum purchase amounts', () => {
    expect(
      extractCashbackAmounts(`${category.subtitle}\n${category.description}`),
    ).toEqual({
      maxCashbackAmount: 2000,
      minPurchaseAmount: 5000,
    });
  });

  it('extracts a cashback limit sentence', () => {
    expect(extractCashbackAmounts('Лимит кешбэка 500 ₽.')).toMatchObject({
      maxCashbackAmount: 500,
    });
  });

  it('removes VTB boilerplate while preserving MCC and payment restrictions', () => {
    expect(cleanVtbDescription(category.description)).toBe(
      'MCC: 5691\nПри оплате по СБП кешбэк не начисляется',
    );
  });

  it('enriches a category before cleaning its VTB description', () => {
    expect(enrichCashbackCategory('vtb', category)).toMatchObject({
      maxCashbackAmount: 2000,
      minPurchaseAmount: 5000,
      description: 'MCC: 5691\nПри оплате по СБП кешбэк не начисляется',
    });
  });
});
