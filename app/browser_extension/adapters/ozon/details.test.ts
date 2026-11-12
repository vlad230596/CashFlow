// @vitest-environment happy-dom
// @vitest-environment-options {"url": "https://finance.ozon.ru/lk/cashback"}
import { afterEach, describe, expect, it, vi } from 'vitest';
import { runProbe } from '../probe-runner';
import { enrichOzonDescriptions, extractOzonCashbackCategories } from './cashback';

/*
 * Regression: an Ozon category reads «5% Образование — Школы, вузы и прочее —
 * Кешбэк до 1 500 ₽», yet the import had no cap. Its detail sheet starts with
 * «5% Образование», while the adapter looked for a sheet starting with the
 * bare name, so the sheet text (and the cap) was never captured. All names
 * and amounts below are synthetic.
 */

const FAST = { timeoutMs: 800, quietMs: 60, pollMs: 15, advanceEveryMs: 0, maxAdvances: 0 };

afterEach(() => {
  document.body.innerHTML = '';
  vi.useRealTimers();
});

function savedMonth() {
  vi.useFakeTimers({ toFake: ['Date'], shouldAdvanceTime: true });
  vi.setSystemTime(new Date(2026, 10, 12));
  document.body.innerHTML = `
    <div data-testid="cashback-help-container"><span>Копится до 11 декабря</span></div>
    <div data-testid="categories-container">
      <h2>Категории в ноябре</h2>
      <div data-testid="carousel-item"><div role="button"><img src="https://cdn.example.test/a.png"><span>5% Тестовое обучение</span></div></div>
      <div data-testid="carousel-item"><div role="button"><img src="https://cdn.example.test/b.png"><span>3% Тестовая химчистка</span></div></div>
    </div>`;
  for (const button of document.querySelectorAll<HTMLElement>('[data-testid="carousel-item"] [role="button"]')) {
    button.addEventListener('click', () => {
      const title = button.textContent!.trim();
      const sheet = document.createElement('div');
      sheet.className = 'bottom-sheet-main-x1';
      // Sheets are titled «N% Name»; the close button comes first.
      sheet.innerHTML = `<button aria-label="Закрыть"></button><h3>${title}</h3>` +
        `<p>Тестовые учреждения</p><p>Кешбэк до 1&nbsp;500 ₽</p><p>MCC: 8299</p>`;
      sheet.querySelector('button')!.addEventListener('click', () => sheet.remove());
      setTimeout(() => document.body.append(sheet), 10);
    });
  }
}

describe('Ozon cashback cap', () => {
  it('reads the cap and conditions from a sheet titled with the percentage', async () => {
    savedMonth();
    const categories = await enrichOzonDescriptions(extractOzonCashbackCategories());
    const education = categories.find((category) => category.name === 'Тестовое обучение')!;
    expect(education.maxCashbackAmount).toBe(1500);
    expect(education.description).toContain('Тестовые учреждения');
    expect(education.description).toContain('MCC: 8299');
    expect(education.confirmed).toBe(true);
    // Each sheet is closed after reading.
    expect(document.querySelectorAll('[class*="bottom-sheet-main"]')).toHaveLength(0);
  });

  it('exports the cap through a full probe', async () => {
    savedMonth();
    const cache = new Map<string, string>();
    const probe = await runProbe({
      bankId: 'ozon',
      read: () => extractOzonCashbackCategories(),
      enrich: (categories) => enrichOzonDescriptions(categories, cache),
    }, 'thorough', undefined, FAST);
    expect(probe.categories.map((category) => [category.name, category.maxCashbackAmount])).toEqual([
      ['Тестовое обучение', 1500],
      ['Тестовая химчистка', 1500],
    ]);
  });

  it('reads the cap printed on a card of the selection list', () => {
    document.body.innerHTML = `
      <div data-testid="selection-title">Повышенный кешбэк</div>
      <div data-testid="favorite-category-list">
        <div role="button" aria-checked="true">
          <img src="https://cdn.example.test/c.png">
          <div><span>5% Тестовое обучение</span></div>
          <div><span>Тестовые школы и курсы</span><span><svg></svg>Кешбэк до 1 500 ₽</span></div>
        </div>
        <div role="button" aria-checked="false">
          <img src="https://cdn.example.test/d.png">
          <div><span>1% Все тестовые покупки</span></div>
          <div><span>Без ограничений</span></div>
        </div>
      </div>`;
    const categories = extractOzonCashbackCategories();
    expect(categories.map((category) => [category.name, category.selected, category.maxCashbackAmount])).toEqual([
      ['Тестовое обучение', true, 1500],
      ['Все тестовые покупки', false, null],
    ]);
    expect(categories[0]!.description).toBe('Тестовые школы и курсы\nКешбэк до 1 500 ₽');
  });
});
