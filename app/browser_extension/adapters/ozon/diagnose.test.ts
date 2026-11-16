// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from 'vitest';
import { runProbe, type ProbeTiming } from '../probe-runner';
import { diagnoseOzonPage, extractOzonCashbackCategories } from './cashback';

const FAST: ProbeTiming = { timeoutMs: 200, quietMs: 30, pollMs: 10, advanceEveryMs: 0, maxAdvances: 0 };

/*
 * An Ozon import ended without categories and the side panel said only
 * «Ожидаю страницу категорий». Each page now explains what it saw. Names are
 * synthetic.
 */

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

const november = () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(new Date(2026, 10, 17));
};

describe('diagnoseOzonPage', () => {
  it('reports a selection page without its list', () => {
    document.body.innerHTML = '<div data-testid="selection-title">Ваши категории в ноябре</div>';
    expect(diagnoseOzonPage([], document, '/lk/favorite-categories-v3')).toEqual([
      expect.stringMatching(/favorite-category-list/),
    ]);
  });

  it('reports a selection list whose cards are not in «N% Name» form', () => {
    document.body.innerHTML = '<div data-testid="favorite-category-list"><div role="button"><span>Тестовые книги</span><span>5 %</span></div></div>';
    expect(diagnoseOzonPage(extractOzonCashbackCategories(), document, '/lk/favorite-categories-v3'))
      .toEqual([expect.stringMatching(/не в формате/)]);
  });

  it('reports a cashback page without the category block', () => {
    document.body.innerHTML = '<main><h1>Кешбэк</h1></main>';
    expect(diagnoseOzonPage([], document, '/lk/cashback/')).toEqual([expect.stringMatching(/categories-container/)]);
  });

  it('reports an empty category block', () => {
    document.body.innerHTML = '<div data-testid="categories-container"><h2>Категории в ноябре</h2></div>';
    expect(diagnoseOzonPage([], document, '/lk/cashback')).toEqual([expect.stringMatching(/нет carousel-item/)]);
  });

  it('reports cards it could not parse', () => {
    document.body.innerHTML = `<div data-testid="categories-container"><h2>Категории в ноябре</h2>
      <div data-testid="carousel-item"><span>Тестовые книги</span></div></div>`;
    expect(diagnoseOzonPage([], document, '/lk/cashback')).toEqual(['карточек 1, но ни одна не в формате «N% Название»']);
  });

  it('reports another month and categories whose detail sheet was not read', () => {
    november();
    document.body.innerHTML = `<div data-testid="categories-container"><h2>Категории в октябре</h2>
      <div data-testid="carousel-item"><div role="button"><span>5% Тестовые книги</span></div></div>
      <div data-testid="carousel-item"><div role="button"><span>3% Тестовый спорт</span></div></div></div>`;
    const categories = extractOzonCashbackCategories()
      .map((category) => category.name === 'Тестовый спорт' ? { ...category, description: 'Кешбэк до 1 000 ₽' } : category);
    expect(diagnoseOzonPage(categories, document, '/lk/cashback')).toEqual([
      'блок показывает «Категории в октябре», а не текущий месяц — категории не отмечены как подтверждённые',
      'не прочитаны условия и лимит: 5% Тестовые книги',
    ]);
  });

  it('is silent for a complete current-month page', () => {
    november();
    document.body.innerHTML = `<div data-testid="categories-container"><h2>Категории в ноябре</h2>
      <div data-testid="carousel-item"><div role="button"><span>5% Тестовые книги</span></div></div></div>`;
    const categories = extractOzonCashbackCategories().map((category) => ({ ...category, description: 'Условия' }));
    expect(diagnoseOzonPage(categories, document, '/lk/cashback')).toEqual([]);
  });

  it('reaches the side panel through the probe', async () => {
    document.body.innerHTML = '<main><h1>Кешбэк</h1></main>';
    const probe = await runProbe({
      bankId: 'ozon',
      read: () => extractOzonCashbackCategories(),
      diagnose: (result) => diagnoseOzonPage(result.categories, document, '/lk/cashback'),
    }, 'thorough', undefined, FAST);
    expect(probe.notes).toEqual([expect.stringMatching(/categories-container/)]);
  });

  it('explains an empty page even without a bank-specific diagnosis', async () => {
    const probe = await runProbe({ bankId: 'sber', read: () => [] }, 'thorough', undefined, FAST);
    expect(probe.notes).toEqual([expect.stringMatching(/^на странице не найдено ни одной категории за \d+ с$/)]);
  });

  it('names the right pages when another Ozon page is open', () => {
    expect(diagnoseOzonPage([], document, '/lk/main')).toEqual([
      'открыта страница /lk/main; категории Ozon находятся на /lk/cashback и /lk/favorite-categories-v3',
    ]);
  });
});
