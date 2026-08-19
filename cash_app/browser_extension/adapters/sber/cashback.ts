import type { CashbackCategory } from '../types';

export type SberCashbackCategory = CashbackCategory;

type ParsedSberCategory = Pick<
  SberCashbackCategory,
  'name' | 'percent' | 'percentLabel'
>;

function normalizeText(value: string | null | undefined): string {
  return value?.replace(/\s+/g, ' ').trim() ?? '';
}

export function parseSberCategoryTitle(rawTitle: string): ParsedSberCategory | null {
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

function findMonthLabel(root: ParentNode, available: boolean): string | null {
  const documentText = (root as Document).documentElement?.textContent;
  const text = normalizeText(root.textContent ?? documentText);
  const match = text.match(
    /(?:кешбэк\s+на|категори(?:ю|и|й)\s+на)\s+([а-яё]+)/i,
  );
  if (!match) return null;

  return `${available ? 'Доступно на' : 'Кешбэк на'} ${match[1]}`;
}

function findCheckboxItem(input: HTMLInputElement): HTMLElement | null {
  let element = input.parentElement;

  while (element) {
    const titles = [...element.querySelectorAll<HTMLElement>('p, h2, h3, h4, span')].filter(
      (candidate) => parseSberCategoryTitle(candidate.textContent ?? '') != null,
    );
    if (titles.length === 1 && element.querySelectorAll('input[type="checkbox"]').length === 1) {
      return element;
    }
    element = element.parentElement;
  }

  return null;
}

function categoryFromItem(
  item: HTMLElement,
  selected: boolean,
  group: string | null,
): SberCashbackCategory | null {
  const textElements = [...item.querySelectorAll<HTMLElement>('p, h2, h3, h4, span')];
  const titleElement = textElements.find(
    (element) => parseSberCategoryTitle(element.textContent ?? '') != null,
  );
  const parsedTitle = parseSberCategoryTitle(titleElement?.textContent ?? '');
  if (!titleElement || !parsedTitle) return null;

  const description = textElements
    .map((element) => normalizeText(element.textContent))
    .find((text) => text && text !== normalizeText(titleElement.textContent) && text.length > 3);
  const image = item.querySelector<HTMLImageElement>('img');

  return {
    type: 'standard',
    ...parsedTitle,
    subtitle: null,
    description: description || null,
    iconUrl: image?.currentSrc || image?.src || null,
    iconBackgroundColor: null,
    selected,
    group,
    expiresInLabel: null,
  };
}

export function extractSberCashbackCategories(
  root: ParentNode = document,
): SberCashbackCategory[] {
  const checkboxes = [...root.querySelectorAll<HTMLInputElement>('input[type="checkbox"]')];
  const availableGroup = findMonthLabel(root, true);
  const categories = new Map<string, SberCashbackCategory>();

  for (const checkbox of checkboxes) {
    const item = findCheckboxItem(checkbox);
    if (!item) continue;
    const category = categoryFromItem(item, checkbox.checked, availableGroup);
    if (category) categories.set(`${category.name}\u0000${category.percentLabel}`, category);
  }

  if (categories.size || checkboxes.length) return [...categories.values()];

  const selectedGroup = findMonthLabel(root, false);
  for (const titleElement of root.querySelectorAll<HTMLElement>('p, h2, h3, h4, span')) {
    const parsedTitle = parseSberCategoryTitle(titleElement.textContent ?? '');
    if (!parsedTitle) continue;

    let item = titleElement.parentElement;
    while (item?.parentElement) {
      const matchingTitles = [...item.querySelectorAll<HTMLElement>('p, h2, h3, h4, span')].filter(
        (candidate) => parseSberCategoryTitle(candidate.textContent ?? '') != null,
      );
      if (matchingTitles.length === 1 && normalizeText(item.innerText).length > normalizeText(titleElement.innerText).length) {
        break;
      }
      item = item.parentElement;
    }

    if (!item) continue;
    const category = categoryFromItem(item, true, selectedGroup);
    if (category) categories.set(`${category.name}\u0000${category.percentLabel}`, category);
  }

  return [...categories.values()];
}
