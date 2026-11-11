// @vitest-environment happy-dom
// @vitest-environment-options {"url": "https://sp.yandex.ru/cashback/current"}
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { enrichAlfaDescriptions, extractAlfaCashbackCategories, hasAlfaCategoryList, openAlfaCategoryProgram } from './alfa/cashback';
import { enrichOzonDescriptions, extractOzonCashbackCategories } from './ozon/cashback';
import { createProbeHandler, runProbe, type ProbeSource, type ProbeTiming } from './probe-runner';
import { extractSberCashbackCategories } from './sber/cashback';
import { expandYandexCategories, extractYandexCashbackCategories } from './yandex/cashback';

/*
 * Fixtures in __fixtures__ are synthetic bank pages: they keep only the
 * attributes and nesting the adapters rely on; every name, percentage and
 * amount is invented. `<template data-template>` blocks hold rows that the
 * tests render later to imitate lazy, chunked or virtualised SPA rendering.
 */

const FAST: ProbeTiming = { timeoutMs: 1500, quietMs: 120, pollMs: 20, advanceEveryMs: 250, maxAdvances: 3 };
const timings = { passive: FAST, thorough: { ...FAST, quietMs: 160 } };
const wait = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function load(name: string) {
  document.body.innerHTML = readFileSync(join(__dirname, '__fixtures__', name), 'utf8');
}

function templateNodes(name: string): Element[] {
  const template = document.querySelector<HTMLTemplateElement>(`template[data-template="${name}"]`)!;
  return [...template.content.children].map((node) => node.cloneNode(true) as Element);
}

const names = (categories: Array<{ percentLabel: string | null; name: string }>) =>
  categories.map((category) => `${category.percentLabel} ${category.name}`).sort();

afterEach(() => {
  document.body.innerHTML = '';
  vi.restoreAllMocks();
});

describe('late and partial rendering', () => {
  const sber: ProbeSource = { bankId: 'sber', read: () => extractSberCashbackCategories() };

  it('waits for a list that renders after the probe started', async () => {
    load('sber-select.html');
    expect(extractSberCashbackCategories()).toEqual([]);
    setTimeout(() => document.querySelector('.list')!.append(...templateNodes('sber-rows')), 150);

    const probe = await runProbe(sber, 'passive', undefined, FAST);

    expect(probe.categories).toHaveLength(6);
    expect(probe.capture).toMatchObject({ stable: true, mode: 'passive' });
    expect(probe.authenticationStatus).toBe('authenticated');
    expect(probe.selection).toMatchObject({ selectedCount: 3, maxSelectable: 3, totalOptions: 6 });
  });

  it('collects a list delivered in chunks instead of the first chunk only', async () => {
    load('sber-select.html');
    const rows = templateNodes('sber-rows');
    const list = document.querySelector('.list')!;
    list.append(...rows.slice(0, 2));
    // What a single immediate read (the previous implementation) returned:
    expect(extractSberCashbackCategories()).toHaveLength(2);
    setTimeout(() => list.append(...rows.slice(2, 4)), 70);
    setTimeout(() => list.append(...rows.slice(4)), 140);

    const probe = await runProbe(sber, 'passive', undefined, FAST);

    expect(probe.categories).toHaveLength(6);
    expect(probe.capture?.stable).toBe(true);
  });

  it('keeps rows of a virtualised carousel that are rendered only briefly', async () => {
    load('ozon-cashback.html');
    const items = templateNodes('ozon-items');
    const carousel = document.querySelector('.carousel')!;
    // Only two items exist in the DOM at any time.
    const windows = [[1, 2], [2, 3]];
    carousel.replaceChildren(items[0]!.cloneNode(true), items[1]!.cloneNode(true));
    windows.forEach((visible, index) => setTimeout(() => {
      carousel.replaceChildren(...visible.map((item) => items[item]!.cloneNode(true)));
    }, 60 * (index + 1)));

    const probe = await runProbe({ bankId: 'ozon', read: () => extractOzonCashbackCategories() }, 'passive', undefined, FAST);

    expect(names(probe.categories)).toEqual(['1,5% Тестовые покупки', '10% Тестовые цветы', '3% Тестовый спорт', '5% Тестовые книги']);
    expect(probe.categories.find((category) => category.name === 'Тестовые покупки')?.percent).toBe(1.5);
  });

  it('opens the Alfa program once and waits for the list it loads', async () => {
    load('alfa-cashback.html');
    const program = document.querySelector<HTMLElement>('[data-test-id="cashback-programs-item"]')!;
    const click = vi.fn(() => setTimeout(() => {
      document.querySelector('[data-test-id="category-list"]')!.append(...templateNodes('alfa-list'));
    }, 120));
    program.addEventListener('click', click);

    const probe = await runProbe({
      bankId: 'alfa',
      read: () => hasAlfaCategoryList() ? extractAlfaCashbackCategories() : [],
      advance: (collected) => !collected.length && openAlfaCategoryProgram(),
    }, 'thorough', undefined, timings.thorough);

    expect(click).toHaveBeenCalledOnce();
    expect(probe.capture?.advances).toBe(1);
    expect(names(probe.categories)).toEqual(['2% Тестовый транспорт', '3% Тестовые аптеки', '5% Тестовые кафе', '7% Тестовое такси']);
    expect(probe.categories.filter((category) => category.selected)).toHaveLength(3);
  });

  it('expands a collapsed Yandex list before reporting it', async () => {
    load('yandex-current.html');
    const more = document.querySelector('button')!;
    more.addEventListener('click', () => setTimeout(() => {
      document.querySelector('ul')!.append(...templateNodes('yandex-more'));
      more.remove();
    }, 80));
    expect(extractYandexCashbackCategories()).toHaveLength(2);

    const probe = await runProbe({
      bankId: 'yandex',
      read: () => extractYandexCashbackCategories(),
      advance: () => expandYandexCategories(),
    }, 'passive', undefined, FAST);

    expect(names(probe.categories)).toEqual(['3% Тестовые аптеки', '4% Тестовые книги', '5% Тестовые кафе', '7% Тестовое такси']);
  });

  it('gives up within the time limit on a page without categories', async () => {
    load('sber-select.html');
    const started = Date.now();
    const probe = await runProbe(sber, 'passive', undefined, { ...FAST, timeoutMs: 300 });
    expect(probe.categories).toEqual([]);
    expect(probe.capture?.stable).toBe(false);
    expect(Date.now() - started).toBeLessThan(1000);
  });
});

describe('repeated collect clicks', () => {
  it('shares one capture between overlapping requests', async () => {
    load('sber-select.html');
    document.querySelector('.list')!.append(...templateNodes('sber-rows'));
    const read = vi.fn(() => extractSberCashbackCategories());
    const handle = createProbeHandler({ bankId: 'sber', read }, undefined, timings);

    const [first, second, third] = await Promise.all([handle(), handle(), handle()]);

    expect(second).toBe(first);
    expect(third).toBe(first);
    expect(first.capture?.reads).toBe(read.mock.calls.length);
    expect(first.categories).toHaveLength(6);
  });

  it('runs a clicked (thorough) capture after a running automatic one, never concurrently', async () => {
    load('sber-select.html');
    document.querySelector('.list')!.append(...templateNodes('sber-rows'));
    let active = 0;
    let maxActive = 0;
    const handle = createProbeHandler({
      bankId: 'sber',
      async read() {
        active += 1;
        maxActive = Math.max(maxActive, active);
        await wait(5);
        active -= 1;
        return extractSberCashbackCategories();
      },
    }, undefined, timings);

    const passive = handle('passive');
    await wait(30);
    const thorough = handle('thorough');
    const [automatic, clicked] = await Promise.all([passive, thorough]);

    expect(automatic.capture?.mode).toBe('passive');
    expect(clicked.capture?.mode).toBe('thorough');
    expect(maxActive).toBe(1);
    expect(clicked.categories).toHaveLength(6);
  });

  it('opens each Ozon detail sheet once across repeated probes', async () => {
    load('ozon-cashback.html');
    document.querySelector('.carousel')!.append(...templateNodes('ozon-items'));
    const opened = vi.fn();
    for (const button of document.querySelectorAll<HTMLElement>('[data-testid="carousel-item"] [role="button"]')) {
      button.addEventListener('click', () => {
        const name = button.textContent!.trim().replace(/^[\d,]+%\s*/, '');
        opened(name);
        const sheet = document.createElement('div');
        sheet.className = 'bottom-sheet-main';
        sheet.innerHTML = `<p>${name}</p><p>Условия категории ${name}</p><button>Закрыть</button>`;
        sheet.querySelector('button')!.addEventListener('click', () => sheet.remove());
        setTimeout(() => document.body.append(sheet), 20);
      });
    }
    const cache = new Map<string, string>();
    const source: ProbeSource = {
      bankId: 'ozon',
      read: () => extractOzonCashbackCategories(),
      enrich: (categories) => enrichOzonDescriptions(categories, cache),
    };

    const first = await runProbe(source, 'passive', undefined, FAST);
    const second = await runProbe(source, 'passive', undefined, FAST);

    expect(opened).toHaveBeenCalledTimes(4);
    expect(second.categories.find((category) => category.name === 'Тестовый спорт')?.description)
      .toContain('Условия категории Тестовый спорт');
    expect(first.categories.map((category) => category.description))
      .toEqual(second.categories.map((category) => category.description));
  });
});

describe('Alfa tooltip descriptions', () => {
  it('matches each tooltip to its own category, not by position', async () => {
    load('alfa-cashback.html');
    // Available categories come before the saved ones in the result.
    const list = document.querySelector('[data-test-id="category-list"]')!;
    const [savedA, savedB, ...options] = templateNodes('alfa-list');
    list.append(...options, savedA!, savedB!);
    const categories = await enrichAlfaDescriptions(extractAlfaCashbackCategories());
    const byName = Object.fromEntries(categories.map((category) => [category.name, category.description]));
    expect(byName['Тестовые аптеки']).toBe('Аптеки по MCC 5912');
    expect(byName['Тестовые кафе']).toBe('Кафе и рестораны по MCC 5812, 5814');
    expect(byName['Тестовое такси'] ?? '').not.toContain('MCC');
  });
});
