import { describe, expect, it } from 'vitest';
import { selectSberCategoriesControl, selectSberLoyaltyControl } from './navigation';

describe('selectSberLoyaltyControl', () => {
  it('prefers a loyalty link over unrelated cashback controls', () => {
    expect(selectSberLoyaltyControl([
      { id: 'promo', href: null, text: 'Кешбэк от партнёра' },
      { id: 'loyalty', href: '/app/loyalty/main/categories', text: 'СберСпасибо' },
    ])?.id).toBe('loyalty');
  });

  it('uses the SberSpasibo control when the SPA does not expose an href', () => {
    expect(selectSberLoyaltyControl([
      { id: 'payments', href: null, text: 'Платежи' },
      { id: 'loyalty', href: null, text: 'Бонусы Спасибо' },
    ])?.id).toBe('loyalty');
  });
});

describe('selectSberCategoriesControl', () => {
  it('selects the informational button in the My categories card', () => {
    expect(selectSberCategoriesControl([
      { id: 'other', href: null, text: 'Посмотреть', context: 'Акции' },
      { id: 'categories', href: null, text: 'Посмотреть', context: 'Мои категории Выбирайте каждый месяц' },
    ])?.id).toBe('categories');
  });

  it('selects the category-list button without accepting a selection', () => {
    expect(selectSberCategoriesControl([
      { id: 'select', href: null, text: 'Выбрать', context: 'Мои категории Кешбэк на август' },
    ])?.id).toBe('select');
  });
});
