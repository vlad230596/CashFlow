import { afterEach, describe, expect, it, vi } from 'vitest';
import { navigateSberOfferPage, scanPreviews, tbankSectionButtons, vtbCatalogue } from './page';

const product = {
  productCode: 'shop-1',
  elements: [
    { elementId: 'heading', value: 'Магазин' },
    { elementId: 'description', value: '10% кешбэк' },
    { elementId: 'image', urlImage: '/shop.svg' },
    { elementId: 'body', link: { url: '/products/cashback/shop-1' } },
    { elementId: 'detailedPage', arrayData: [
      { elementId: 'detailedPage-heading-1', value: 'Условия магазина' },
      { elementId: 'detailedPage-description-1', value: 'Покупка от 500 ₽. Лимит 1 000 ₽.' },
      { elementId: 'detailedPage-secondaryButton-1', link: { url: 'https://example.com/rules.pdf' } },
    ] },
  ],
};

afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

it('opens Sber partner routes through the in-app home and catalogue controls', async () => {
  vi.useFakeTimers();
  const state = { href: 'https://online.sberbank.ru/CSAFront/index.do#/', origin: 'https://online.sberbank.ru' };
  vi.stubGlobal('location', state);
  const home = { getAttribute: () => '/app/loyalty/main', click: vi.fn(() => { state.href = `${state.origin}/app/loyalty/main`; }) };
  const catalogue = { innerText: 'Магазины и сервисы', click: vi.fn(() => { state.href = `${state.origin}/app/loyalty/main/partners`; }) };
  vi.stubGlobal('document', {
    querySelector: () => null,
    querySelectorAll: (selector: string) => selector === 'a[href]' ? [home] : selector === 'main button' ? [catalogue] : [],
  });
  const navigation = navigateSberOfferPage(`${state.origin}/app/loyalty/main/partners`);
  await vi.runAllTimersAsync();
  await expect(navigation).resolves.toBe(true);
  expect(home.click).toHaveBeenCalledOnce();
  expect(catalogue.click).toHaveBeenCalledOnce();
});

it('leaves the October category screens through their back links before opening Sber partners', async () => {
  vi.useFakeTimers();
  const state = { href: 'https://online.sberbank.ru/app/loyalty/main/categories/select', origin: 'https://online.sberbank.ru' };
  vi.stubGlobal('location', state);
  const back = { innerText: 'Назад', href: `${state.origin}/app/loyalty/main/categories`, click: vi.fn(() => { state.href = back.href; }) };
  const home = { innerText: 'Назад', href: `${state.origin}/app/loyalty/main`, click: vi.fn(() => { state.href = home.href; }) };
  const partners = { innerText: 'Магазины и сервисы', click: vi.fn(() => { state.href = `${state.origin}/app/loyalty/main/partners`; }) };
  vi.stubGlobal('document', {
    querySelector: () => null,
    querySelectorAll: (selector: string) => selector === 'main a[href]'
      ? state.href.endsWith('/categories/select') ? [back] : state.href.endsWith('/categories') ? [home] : []
      : selector === 'main button' && state.href.endsWith('/main') ? [partners] : [],
  });
  const navigation = navigateSberOfferPage(`${state.origin}/app/loyalty/main/partners`);
  await vi.runAllTimersAsync();
  await expect(navigation).resolves.toBe(true);
  expect(back.click).toHaveBeenCalledOnce();
  expect(home.click).toHaveBeenCalledOnce();
  expect(partners.click).toHaveBeenCalledOnce();
});

it('expands the Sber partner list before opening an offer outside the first page', async () => {
  vi.useFakeTimers();
  const origin = 'https://online.sberbank.ru';
  const state = { href: `${origin}/app/loyalty/main/partners`, origin, expanded: false };
  vi.stubGlobal('location', state);
  const targetUrl = `${origin}/app/loyalty/main/partner?id=42`;
  const more = { innerText: 'Показать ещё', click: vi.fn(() => { state.expanded = true; }) };
  const offer = { href: targetUrl, click: vi.fn(() => { state.href = targetUrl; }) };
  vi.stubGlobal('document', {
    querySelectorAll: (selector: string) => selector === '[role="dialog"]' ? []
      : selector === 'main a[href]' ? state.expanded ? [offer] : []
      : selector === 'main button' ? state.expanded ? [] : [more] : [],
  });
  const navigation = navigateSberOfferPage(targetUrl);
  await vi.runAllTimersAsync();
  await expect(navigation).resolves.toBe(true);
  expect(more.click).toHaveBeenCalledOnce();
  expect(offer.click).toHaveBeenCalledOnce();
});

it('reads both named and numeric T-Bank sections without nested controls', () => {
  const button = (qa: string) => ({ getAttribute: () => qa });
  const nodes = [button('desktop-bonuses-all-categories-category-1'), button('desktop-bonuses-all-categories-category-food'), button('desktop-bonuses-all-categories-category-offline_service'), button('desktop-bonuses-all-categories-category-food-title')];
  vi.stubGlobal('document', { querySelectorAll: () => nodes });
  expect(tbankSectionButtons()).toEqual(nodes.slice(0, 3));
});

describe('Ozon extended offers', () => {
  it('allows opening an inactive promotion while retaining its pre-opening state', () => {
    vi.stubGlobal('location', { href: 'https://finance.ozon.ru/lk/promotions?filter=all' });
    const nodes: Record<string, unknown> = {
      '.card-body-text .title': { innerText: 'Магазин' },
      '.percent': { innerText: '10%' },
      '[data-testid="activate-promo"]': { innerText: 'Подключить' },
    };
    vi.stubGlobal('document', { querySelectorAll: () => [{
      innerText: 'Магазин 10% Подключить', querySelector: (selector: string) => nodes[selector] ?? null,
    }] });
    expect(scanPreviews('ozon')[0]).toMatchObject({
      name: 'Магазин', selected: false, canOpenSafely: true,
    });
  });

  it('collects the Ozon CSS logo when the card has no img element', () => {
    vi.stubGlobal('location', { href: 'https://finance.ozon.ru/lk/promotions?filter=all' });
    const logo = {};
    vi.stubGlobal('getComputedStyle', () => ({ backgroundImage: 'url("https://cdn1.ozone.ru/logo.png")' }));
    vi.stubGlobal('document', { querySelectorAll: () => [{
      innerText: 'KARI 8%',
      querySelector: (selector: string) => selector === '.card-body-text .title' ? { innerText: 'KARI' }
        : selector === '.percent' ? { innerText: '8%' }
        : selector === '.card-body .logo .image' ? logo : null,
    }] });
    expect(scanPreviews('ozon')[0]?.iconUrl).toBe('https://cdn1.ozone.ru/logo.png');
  });
});

describe('VTB extended catalogue', () => {
  it('reads complete API details and deduplicates an offer appearing in two groups', async () => {
    vi.stubGlobal('location', { href: 'https://online.sbpvtb.ru/products/cashback/catalogue' });
    const result = await vtbCatalogue({ locations: [{
      locationName: 'CASHBACK_PAGE', positions: [{ positionName: 'CATEGORY', categories: [
        { categoryCode: 'food', elements: [{ elementId: 'heading', value: 'Еда' }], products: [product] },
        { categoryCode: 'online', elements: [{ elementId: 'heading', value: 'Онлайн' }], products: [product] },
      ] }],
    }] });
    expect(result).toHaveLength(1);
    expect(result[0]?.preview).toMatchObject({
      id: 'catalogue-shop-1', name: 'Магазин', percent: 10, group: 'Еда, Онлайн',
      iconUrl: 'https://h2.sbpvtb.ru/shop.svg',
    });
    expect(result[0]?.detail.conditions).toContain('Лимит 1 000 ₽');
    expect(result[0]?.detail.links).toEqual([{ text: 'Правила', url: 'https://example.com/rules.pdf' }]);
  });
});
