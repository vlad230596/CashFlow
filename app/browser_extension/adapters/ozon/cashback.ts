import type { CashbackCategory } from '../types';

export type OzonCashbackCategory = CashbackCategory;

type ParsedOzonCategoryTitle = Pick<
  OzonCashbackCategory,
  'name' | 'percent' | 'percentLabel'
>;

function normalizeText(value: string | null | undefined): string {
  return value?.replace(/\s+/g, ' ').trim() ?? '';
}

export function parseOzonCategoryTitle(rawTitle: string): ParsedOzonCategoryTitle | null {
  const title = normalizeText(rawTitle);
  const match = title.match(/^(\d+(?:[.,]\d+)?)\s*%\s+(.+)$/);
  if (!match) return null;

  const percent = match[1]!;
  return {
    name: match[2]!,
    percent: Number(percent.replace(',', '.')),
    percentLabel: `${percent}%`,
  };
}

function findCategoryGroup(container: HTMLElement): string | null {
  const heading = [...container.querySelectorAll<HTMLElement>('h1, h2, h3, div')]
    .map((element) => normalizeText(element.textContent))
    .find((text) => /^Категории в\s+/i.test(text));
  return heading || null;
}

function findExpiryLabel(root: ParentNode): string | null {
  const cashbackRoot = root.querySelector<HTMLElement>('[data-testid="cashback-help-container"]');
  const candidates = cashbackRoot?.querySelectorAll<HTMLElement>('*') ?? [];
  return (
    [...candidates]
      .map((element) => normalizeText(element.textContent))
      .filter((text) => /^Копится до\s+\S+(?:\s+\S+)?$/i.test(text))
      .sort((left, right) => left.length - right.length)[0] ?? null
  );
}

function extractOzonFavoriteCategories(root: ParentNode): OzonCashbackCategory[] {
  const list = root.querySelector<HTMLElement>('[data-testid="favorite-category-list"]');
  if (!list) return [];

  const categories = new Map<string, OzonCashbackCategory>();
  const leaves = [...list.querySelectorAll<HTMLElement>('div, span, p')]
    .filter((element) => element.children.length === 0);
  for (const leaf of leaves) {
    const parsed = parseOzonCategoryTitle(leaf.textContent ?? '');
    if (!parsed) continue;

    let item = leaf.parentElement;
    while (item?.parentElement && item.parentElement !== list) {
      const parsedLeaves = [...item.querySelectorAll<HTMLElement>('div, span, p')]
        .filter((element) => element.children.length === 0)
        .filter((element) => parseOzonCategoryTitle(element.textContent ?? '') != null);
      if (parsedLeaves.length === 1 && (item.matches('[role="button"]') || item.querySelector('img, input'))) break;
      item = item.parentElement;
    }
    if (!item) continue;

    const image = item.querySelector<HTMLImageElement>('img');
    const input = item.querySelector<HTMLInputElement>('input[type="checkbox"], input[type="radio"]');
    const selected = input?.checked ?? item.getAttribute('aria-checked') === 'true';
    const description = [...item.querySelectorAll<HTMLElement>('div, span, p')]
      .filter((element) => element.children.length === 0)
      .map((element) => normalizeText(element.textContent))
      .find((text) => text && parseOzonCategoryTitle(text) == null) ?? null;
    const category: OzonCashbackCategory = {
      type: 'standard',
      ...parsed,
      subtitle: null,
      description,
      iconUrl: image?.currentSrc || image?.src || null,
      iconBackgroundColor: null,
      selected,
      group: 'Доступные категории',
      expiresInLabel: null,
    };
    categories.set(`${category.name}\u0000${category.percentLabel}`, category);
  }
  return [...categories.values()];
}

export function extractOzonCashbackCategories(
  root: ParentNode = document,
): OzonCashbackCategory[] {
  const favoriteCategories = extractOzonFavoriteCategories(root);
  if (favoriteCategories.length) return favoriteCategories;

  const container = root.querySelector<HTMLElement>('[data-testid="categories-container"]');
  if (!container) return [];

  const group = findCategoryGroup(container);
  const expiresInLabel = findExpiryLabel(root);
  const categories: OzonCashbackCategory[] = [];

  for (const item of container.querySelectorAll<HTMLElement>('[data-testid="carousel-item"]')) {
    const title = [...item.querySelectorAll<HTMLElement>('div, span')]
      .map((element) => normalizeText(element.textContent))
      .find((text) => parseOzonCategoryTitle(text) != null);
    const parsed = parseOzonCategoryTitle(title ?? '');
    if (!parsed) continue;

    const image = item.querySelector<HTMLImageElement>('img');
    categories.push({
      type: 'standard',
      ...parsed,
      subtitle: expiresInLabel,
      description: null,
      iconUrl: image?.currentSrc || image?.src || null,
      iconBackgroundColor: null,
      selected: true,
      group,
      expiresInLabel,
    });
  }

  return categories;
}

function detailTextForCategory(name: string): string | null {
  const sheets = [...document.querySelectorAll<HTMLElement>('[class*="bottom-sheet-main"]')];
  const sheet = sheets.reverse().find((candidate) => {
    const firstLine = candidate.innerText
      .split(/\n+/)
      .map(normalizeText)
      .find(Boolean);
    return firstLine === name;
  });
  if (!sheet) return null;

  const lines = sheet.innerText
    .split(/\n+/)
    .map(normalizeText)
    .filter((line) => line && line !== name && line !== 'Закрыть');
  return lines.length ? lines.join('\n') : null;
}

function waitForDetail(name: string, timeoutMs = 1200): Promise<string | null> {
  const startedAt = Date.now();
  return new Promise((resolve) => {
    const check = () => {
      const description = detailTextForCategory(name);
      if (description || Date.now() - startedAt >= timeoutMs) {
        resolve(description);
        return;
      }
      window.setTimeout(check, 40);
    };
    check();
  });
}

export async function extractOzonCashbackCategoriesWithDetails(): Promise<
  OzonCashbackCategory[]
> {
  const categories = extractOzonCashbackCategories();
  if (document.querySelector('[data-testid="favorite-category-list"]')) return categories;
  const items = [
    ...document.querySelectorAll<HTMLElement>(
      '[data-testid="categories-container"] [data-testid="carousel-item"]',
    ),
  ];

  for (const [index, category] of categories.entries()) {
    const cachedDescription = detailTextForCategory(category.name);
    if (cachedDescription) {
      category.description = cachedDescription;
      continue;
    }

    const infoButton = items[index]?.querySelector<HTMLElement>('[role="button"]');
    if (!infoButton) continue;
    infoButton.click();
    category.description = await waitForDetail(category.name);

    const sheet = [...document.querySelectorAll<HTMLElement>('[class*="bottom-sheet-main"]')]
      .reverse()
      .find((candidate) => normalizeText(candidate.innerText).startsWith(category.name));
    const closeButton = [...(sheet?.querySelectorAll<HTMLButtonElement>('button') ?? [])].find(
      (button) => normalizeText(button.innerText) === 'Закрыть',
    );
    closeButton?.click();
  }

  return categories;
}
