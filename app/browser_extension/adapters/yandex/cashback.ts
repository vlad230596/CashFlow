import type { CashbackCategory } from '../types';

export type YandexCashbackCategory = CashbackCategory;

type ParsedYandexCardText = Pick<
  YandexCashbackCategory,
  'name' | 'percent' | 'percentLabel' | 'subtitle' | 'description' | 'expiresInLabel'
>;

export function parseYandexPercent(rawValue: string): Pick<
  YandexCashbackCategory,
  'percent' | 'percentLabel'
> {
  const value = rawValue.replace(/\s+/g, ' ').trim();
  const match = value.match(/(\d+(?:[.,]\d+)?)\s*%/);

  if (!match) return { percent: null, percentLabel: null };

  const number = match[1]!;
  const prefix = /^до\s/i.test(value) ? 'до ' : '';

  return {
    percent: Number(number.replace(',', '.')),
    percentLabel: `${prefix}${number}%`,
  };
}

export function parseYandexCashbackCardText(rawText: string): ParsedYandexCardText | null {
  const lines = rawText
    .split(/\n+/)
    .map((line) => line.replace(/\s+/g, ' ').trim())
    .filter(Boolean);
  const percentIndex = lines.findIndex((line) => /^\d+(?:[.,]\d+)?\s*%$/.test(line));

  if (!lines[0] || percentIndex < 0) return null;

  const parsedPercent = parseYandexPercent(lines[percentIndex]!);
  const expiresInLabel =
    lines.find((line) => /^ещё\s+\d+\s+(?:день|дня|дней)$/i.test(line)) ?? null;
  const details = lines.filter(
    (line, index) => index !== 0 && index !== percentIndex && line !== expiresInLabel,
  );

  return {
    name: lines[0],
    ...parsedPercent,
    subtitle: expiresInLabel,
    description: details.length ? details.join('\n') : null,
    expiresInLabel,
  };
}

function extractFullYandexCashbackCategories(root: ParentNode): YandexCashbackCategory[] {
  const categories = new Map<string, YandexCashbackCategory>();

  for (const item of root.querySelectorAll<HTMLElement>(
    'li[class*="SelectorListItem_block"]',
  )) {
    const name = item
      .querySelector<HTMLElement>('[class*="SelectorListItem_title"]')
      ?.textContent?.replace(/\s+/g, ' ')
      .trim();
    const percentText = item
      .querySelector<HTMLElement>('[class*="PlusCashback_percent"]')
      ?.textContent?.trim();
    if (!name || !percentText) continue;

    const parsedPercent = parseYandexPercent(percentText);
    if (parsedPercent.percent == null) continue;

    const expiresInLabel =
      item
        .querySelector<HTMLElement>('[class*="SelectorListItem_endSlotLabel"]')
        ?.textContent?.replace(/\s+/g, ' ')
        .trim() || null;
    const description =
      item
        .querySelector<HTMLElement>('[class*="SelectorListItem_subtitle"]')
        ?.textContent?.replace(/\s+/g, ' ')
        .trim() || null;

    const list = item.closest<HTMLUListElement>('ul[class*="List_block"]');
    const group = list?.previousElementSibling?.textContent?.replace(/\s+/g, ' ').trim() || null;
    const image = item.querySelector<HTMLImageElement>('img');
    const icon = image?.closest<HTMLElement>('[class*="CashbackIcon_listItemIcon"]');
    const category: YandexCashbackCategory = {
      type: 'standard',
      name,
      ...parsedPercent,
      subtitle: expiresInLabel,
      description,
      expiresInLabel,
      iconUrl: image?.currentSrc || image?.src || null,
      iconBackgroundColor: icon ? getComputedStyle(icon).backgroundColor : null,
      selected: true,
      group,
    };

    categories.set(`${category.name}\u0000${category.percentLabel}`, category);
  }

  return [...categories.values()];
}

function extractYandexSelectorCategories(root: ParentNode): YandexCashbackCategory[] {
  const categories = new Map<string, YandexCashbackCategory>();

  for (const item of root.querySelectorAll<HTMLElement>(
    '[data-testid="selector-page-list-item"], [data-test-id="selector-page-list-item"]',
  )) {
    const lines = item.innerText
      .split(/\n+/)
      .map((line) => line.replace(/\s+/g, ' ').trim())
      .filter(Boolean);
    const title = item
      .querySelector<HTMLElement>('[class*="ListItem_title__"]')
      ?.textContent?.replace(/\s+/g, ' ').trim()
      ?? lines.find((line) => /^[−-]?\d+(?:[.,]\d+)?\s*%\s+\S/.test(line));
    const match = title?.match(/^([−-]?\d+(?:[.,]\d+)?)\s*%\s+(.+?)$/);
    if (!match) continue;

    const image = item.querySelector<HTMLImageElement>('img');
    const input = item.querySelector<HTMLInputElement>('input[type="checkbox"], input[type="radio"]');
    const selected = input?.checked ?? item.getAttribute('aria-checked') === 'true';
    const percentText = match[1]!;
    const category: YandexCashbackCategory = {
      type: 'standard',
      name: match[2]!,
      percent: Math.abs(Number(percentText.replace('−', '-').replace(',', '.'))),
      percentLabel: `${percentText}%`,
      subtitle: null,
      description: item
        .querySelector<HTMLElement>('[class*="ListItem_descriptionSecondary"]')
        ?.textContent?.replace(/\s+/g, ' ').trim() || null,
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

export function extractYandexCashbackCategories(
  root: ParentNode = document,
): YandexCashbackCategory[] {
  const selectorCategories = extractYandexSelectorCategories(root);
  if (selectorCategories.length) return selectorCategories;

  const fullCategories = extractFullYandexCashbackCategories(root);
  if (fullCategories.length) return fullCategories;

  const cards = root.querySelectorAll<HTMLElement>(
    '[class*="CashbackStatusWidget-module__cashbackContainer"]',
  );
  const categories = new Map<string, YandexCashbackCategory>();

  for (const card of cards) {
    const image = card.querySelector<HTMLImageElement>('img[alt]');
    const name = image?.alt.replace(/\s+/g, ' ').trim();
    if (!image || !name) continue;

    const parsedPercent = parseYandexPercent(card.innerText);
    if (parsedPercent.percent == null) continue;

    const icon = image.parentElement;
    const category: YandexCashbackCategory = {
      type: 'standard',
      name,
      ...parsedPercent,
      subtitle: null,
      description: null,
      iconUrl: image.currentSrc || image.src || null,
      iconBackgroundColor: icon ? getComputedStyle(icon).backgroundColor : null,
      selected: true,
      group: 'Выгода с Пэй',
      expiresInLabel: null,
    };

    categories.set(`${category.name}\u0000${category.percentLabel}`, category);
  }

  return [...categories.values()];
}
