import type { CashbackCategory } from '../types';
import { showsCurrentCashbackMonth } from '../monthly-confirmation';
import { extractCashbackAmounts } from '../cashback-amounts';

export type OzonCashbackCategory = CashbackCategory;

type ParsedOzonCategoryTitle = Pick<
  OzonCashbackCategory,
  'name' | 'percent' | 'percentLabel'
>;

function normalizeText(value: string | null | undefined): string {
  return value?.replace(/\s+/g, ' ').trim() ?? '';
}

/**
 * Visible text lines of an element, read from text nodes. `innerText` is
 * empty in Chromium background tabs, which collection now opens for Ozon.
 */
export function ozonTextLines(element: Element | null | undefined): string[] {
  if (!element) return [];
  const lines: string[] = [];
  let parent: Element | null = null;
  const doc = element.ownerDocument ?? document;
  const walker = doc.createTreeWalker(element, 4 /* NodeFilter.SHOW_TEXT */);
  for (let node = walker.nextNode(); node; node = walker.nextNode()) {
    const host = node.parentElement;
    if (host?.closest('script, style, template, [hidden], [aria-hidden="true"]')) continue;
    const text = normalizeText(node.nodeValue);
    if (!text) continue;
    // Adjacent text nodes of one element form one line.
    if (host === parent && lines.length) lines[lines.length - 1] = normalizeText(`${lines.at(-1)} ${text}`);
    else lines.push(text);
    parent = host;
  }
  return lines;
}

/**
 * Card or sheet text without the title and service labels, e.g.
 * «Школы, вузы и прочее» and «Кешбэк до 1 500 ₽».
 */
function detailLines(lines: string[], title: ParsedOzonCategoryTitle): string[] {
  return [...new Set(lines.filter((line) => {
    const parsed = parseOzonCategoryTitle(line);
    if (parsed) return false;
    return line !== title.name && !/^(?:Закрыть|Понятно|Подробнее|Выбрать|Выбрано)$/i.test(line);
  }))];
}

function withDetails(
  category: OzonCashbackCategory,
  lines: string[],
): OzonCashbackCategory {
  const text = lines.join('\n');
  if (!text) return category;
  const amounts = extractCashbackAmounts(text);
  return {
    ...category,
    description: text,
    maxCashbackAmount: amounts.maxCashbackAmount ?? category.maxCashbackAmount ?? null,
    minPurchaseAmount: amounts.minPurchaseAmount ?? category.minPurchaseAmount ?? null,
  };
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

export function isOzonSavedCategorySummary(
  heading: string | null,
  pathname: string,
  hasSelectionControls: boolean,
): boolean {
  return pathname === '/lk/cashback' &&
    /^Категории в\s+/i.test(heading ?? '') &&
    showsCurrentCashbackMonth(heading ?? '') && !hasSelectionControls;
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

  const heading = normalizeText(root.querySelector('[data-testid="selection-title"]')?.textContent);
  const saved = /^Ваши категории в\s+/i.test(heading) &&
    showsCurrentCashbackMonth(heading) &&
    !list.querySelector('input[type="checkbox"], input[type="radio"], [role="checkbox"], [role="radio"]');

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
    const selected = saved || (input?.checked ?? item.getAttribute('aria-checked') === 'true');
    const category: OzonCashbackCategory = withDetails({
      type: 'standard',
      ...parsed,
      subtitle: null,
      description: null,
      iconUrl: image?.currentSrc || image?.src || null,
      iconBackgroundColor: null,
      selected,
      confirmed: saved,
      group: saved ? heading : 'Доступные категории',
      expiresInLabel: null,
    }, detailLines(ozonTextLines(item), parsed));
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
  const confirmed = isOzonSavedCategorySummary(
    group,
    typeof location === 'undefined' ? '' : location.pathname,
    Boolean(container.querySelector('input[type="checkbox"], input[type="radio"], [role="checkbox"], [role="radio"]')),
  );
  const expiresInLabel = findExpiryLabel(root);
  const categories: OzonCashbackCategory[] = [];

  for (const item of container.querySelectorAll<HTMLElement>('[data-testid="carousel-item"]')) {
    const title = [...item.querySelectorAll<HTMLElement>('div, span')]
      .map((element) => normalizeText(element.textContent))
      .find((text) => parseOzonCategoryTitle(text) != null);
    const parsed = parseOzonCategoryTitle(title ?? '');
    if (!parsed) continue;

    const image = item.querySelector<HTMLImageElement>('img');
    const lines = detailLines(ozonTextLines(item), parsed)
      .filter((line) => line !== expiresInLabel);
    categories.push(withDetails({
      type: 'standard',
      ...parsed,
      subtitle: expiresInLabel,
      description: null,
      iconUrl: image?.currentSrc || image?.src || null,
      iconBackgroundColor: null,
      selected: true,
      confirmed,
      group,
      expiresInLabel,
    }, lines));
  }

  return categories;
}

const SHEET_SELECTOR = '[class*="bottom-sheet-main"], [role="dialog"], [aria-modal="true"]';

type CategoryTitle = Pick<OzonCashbackCategory, 'name' | 'percentLabel'>;

/** A sheet title is either «Образование» or «5% Образование». */
function isTitleOf(line: string, category: CategoryTitle): boolean {
  if (line === category.name) return true;
  const parsed = parseOzonCategoryTitle(line);
  return parsed?.name === category.name &&
    (category.percentLabel == null || parsed.percentLabel === category.percentLabel);
}

function findDetailSheet(category: CategoryTitle): HTMLElement | null {
  const sheets = [...document.querySelectorAll<HTMLElement>(SHEET_SELECTOR)].reverse();
  // A close button or an icon caption may precede the title.
  return sheets.find((sheet) => ozonTextLines(sheet).slice(0, 3).some((line) => isTitleOf(line, category))) ?? null;
}

function detailTextForCategory(category: CategoryTitle): string | null {
  const sheet = findDetailSheet(category);
  if (!sheet) return null;
  const lines = ozonTextLines(sheet)
    .filter((line) => !isTitleOf(line, category) && !/^(?:Закрыть|Понятно)$/i.test(line));
  return lines.length ? [...new Set(lines)].join('\n') : null;
}

function waitForDetail(category: CategoryTitle, timeoutMs = 1500): Promise<string | null> {
  const startedAt = Date.now();
  return new Promise((resolve) => {
    const check = () => {
      const description = detailTextForCategory(category);
      if (description || Date.now() - startedAt >= timeoutMs) {
        resolve(description);
        return;
      }
      window.setTimeout(check, 40);
    };
    check();
  });
}

function closeDetailSheet(category: CategoryTitle): void {
  const sheet = findDetailSheet(category);
  const close = [...(sheet?.querySelectorAll<HTMLElement>('button, [role="button"]') ?? [])].find((button) =>
    /^(?:Закрыть|Понятно)$/i.test(ozonTextLines(button).join(' ')) ||
    /закрыть/i.test(button.getAttribute('aria-label') ?? ''));
  close?.click();
}

function applyDetail(category: OzonCashbackCategory, description: string): void {
  // The sheet is the complete text of the card; it replaces the card summary.
  const amounts = extractCashbackAmounts(description);
  category.description = description;
  category.maxCashbackAmount = amounts.maxCashbackAmount ?? category.maxCashbackAmount ?? null;
  category.minPurchaseAmount = amounts.minPurchaseAmount ?? category.minPurchaseAmount ?? null;
}

/**
 * Fills descriptions and caps («Кешбэк до 1 500 ₽») from the carousel's
 * detail sheets. Each sheet is opened at most once per page: `cache` keeps
 * the text for later probes.
 */
export async function enrichOzonDescriptions(
  categories: OzonCashbackCategory[],
  cache: Map<string, string> = new Map(),
): Promise<OzonCashbackCategory[]> {
  const result = categories.map((category) => ({ ...category }));
  // The selection list has no detail sheets and must not be clicked.
  if (document.querySelector('[data-testid="favorite-category-list"]')) return result;
  const items = [...document.querySelectorAll<HTMLElement>(
    '[data-testid="categories-container"] [data-testid="carousel-item"]',
  )];
  for (const category of result) {
    const cacheKey = `${category.percentLabel ?? ''}\u0000${category.name}`;
    const cached = cache.get(cacheKey) ?? detailTextForCategory(category);
    if (cached) {
      cache.set(cacheKey, cached);
      applyDetail(category, cached);
      continue;
    }
    // Match the carousel item by its own title rather than by position.
    const item = items.find((candidate) => ozonTextLines(candidate).some((line) => {
      const parsed = parseOzonCategoryTitle(line);
      return parsed?.name === category.name && parsed.percentLabel === category.percentLabel;
    }));
    const infoButton = item?.querySelector<HTMLElement>('[role="button"], button') ?? item;
    if (!infoButton) continue;
    infoButton.click();
    const description = await waitForDetail(category);
    if (description) {
      cache.set(cacheKey, description);
      applyDetail(category, description);
    }
    closeDetailSheet(category);
  }
  return result;
}

export async function extractOzonCashbackCategoriesWithDetails(): Promise<
  OzonCashbackCategory[]
> {
  return enrichOzonDescriptions(extractOzonCashbackCategories());
}
