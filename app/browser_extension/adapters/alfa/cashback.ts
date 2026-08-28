import type { CashbackCategory } from '../types';

export type AlfaCashbackCategory = CashbackCategory;

function normalizeText(value: string | null | undefined): string {
  return value?.replace(/\s+/g, ' ').trim() ?? '';
}

export function isAlfaMonthlySubtitle(value: string): boolean {
  return /(?:^|\s)в\s+(?:январе|феврале|марте|апреле|мае|июне|июле|августе|сентябре|октябре|ноябре|декабре)(?:\s|$)/i.test(
    normalizeText(value),
  );
}

export function parseAlfaCategoryTitle(rawTitle: string): Pick<
  AlfaCashbackCategory,
  'name' | 'percent' | 'percentLabel'
> | null {
  const match = normalizeText(rawTitle).match(/^(\d+(?:[.,]\d+)?)\s*%\s+(.+)$/);
  if (!match) return null;
  const percent = match[1]!;
  return {
    name: match[2]!,
    percent: Number(percent.replace(',', '.')),
    percentLabel: `${percent}%`,
  };
}

function findTitle(root: ParentNode): {
  element: HTMLElement;
  parsed: NonNullable<ReturnType<typeof parseAlfaCategoryTitle>>;
} | null {
  for (const element of root.querySelectorAll<HTMLElement>('p, span, div, h2, h3, h4')) {
    if (element.children.length > 0) continue;
    const parsed = parseAlfaCategoryTitle(element.textContent ?? '');
    if (parsed) return { element, parsed };
  }
  return null;
}

function descriptionFromItem(item: HTMLElement, title: string): string | null {
  const tooltipTarget = item.querySelector<HTMLElement>(
    '[data-test-id="tooltip-category-info-target"]',
  );
  const ariaDescription = normalizeText(
    tooltipTarget?.getAttribute('aria-label') ?? tooltipTarget?.getAttribute('title'),
  );
  if (ariaDescription) return ariaDescription;

  const lines = item.innerText
    .split(/\n+/)
    .map(normalizeText)
    .filter((line) => line && line !== title);
  return lines.length ? [...new Set(lines)].join('\n') : null;
}

function iconUrlFromItem(item: HTMLElement): string | null {
  const image = item.querySelector<HTMLImageElement>('img');
  if (image?.currentSrc || image?.src) return image.currentSrc || image.src;
  const svgImage = item.querySelector<SVGImageElement>('svg image');
  return svgImage?.getAttribute('href') ?? svgImage?.getAttribute('xlink:href') ?? null;
}

function categoryFromItem(item: HTMLElement): AlfaCashbackCategory | null {
  const title = findTitle(item);
  if (!title) return null;
  const titleText = `${title.parsed.percentLabel} ${title.parsed.name}`;
  return {
    type: 'standard',
    ...title.parsed,
    subtitle: null,
    description: descriptionFromItem(item, titleText),
    iconUrl: iconUrlFromItem(item),
    iconBackgroundColor: null,
    selected: true,
    group: 'Уже выбрано',
    expiresInLabel: null,
  };
}

function stackableCategoryFromSubtitle(subtitle: HTMLElement): AlfaCashbackCategory | null {
  if (subtitle.closest('[data-test-id="chosen-category-item"]')) return null;
  const subtitleText = normalizeText(subtitle.textContent);
  if (!isAlfaMonthlySubtitle(subtitleText)) return null;

  let card: HTMLElement | null = subtitle.parentElement;
  let percentText = '';
  for (let depth = 0; card && depth < 7; depth += 1, card = card.parentElement) {
    const percent = [...card.querySelectorAll<HTMLElement>(
      '[data-test-id="cashback-programs-item-title"]',
    )].find((element) => /^\d+(?:[.,]\d+)?\s*%$/.test(normalizeText(element.textContent)));
    if (percent) {
      percentText = normalizeText(percent.textContent);
      break;
    }
  }
  if (!card || !percentText) return null;

  const parsed = parseAlfaCategoryTitle(`${percentText} ${subtitleText}`);
  if (!parsed) return null;
  return {
    type: 'stackable_bonus',
    ...parsed,
    subtitle: null,
    description: descriptionFromItem(card, `${percentText} ${subtitleText}`),
    iconUrl: iconUrlFromItem(card),
    iconBackgroundColor: null,
    selected: true,
    group: 'Суммирующаяся категория',
    expiresInLabel: null,
  };
}

export function extractAlfaCashbackCategories(
  root: ParentNode = document,
): AlfaCashbackCategory[] {
  const categories = new Map<string, AlfaCashbackCategory>();
  for (const item of root.querySelectorAll<HTMLElement>(
    '[data-test-id="chosen-category-item"]',
  )) {
    const category = categoryFromItem(item);
    if (category) categories.set(`standard\u0000${category.percentLabel}\u0000${category.name}`, category);
  }
  for (const subtitle of root.querySelectorAll<HTMLElement>(
    '[data-test-id="cashback-program-card-subtitle"]',
  )) {
    const category = stackableCategoryFromSubtitle(subtitle);
    if (category) categories.set(`stackable\u0000${category.percentLabel}\u0000${category.name}`, category);
  }
  return [...categories.values()];
}

function visibleTooltipText(): string | null {
  const tooltips = [...document.querySelectorAll<HTMLElement>('[role="tooltip"]')];
  const tooltip = tooltips.reverse().find((element) => {
    const rect = element.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0 && getComputedStyle(element).visibility !== 'hidden';
  });
  return normalizeText(tooltip?.innerText) || null;
}

export async function extractAlfaCashbackCategoriesWithDetails(): Promise<AlfaCashbackCategory[]> {
  const categories = extractAlfaCashbackCategories();
  const items = [...document.querySelectorAll<HTMLElement>('[data-test-id="chosen-category-item"]')];
  for (const [index, category] of categories.filter((item) => item.type === 'standard').entries()) {
    const target = items[index]?.querySelector<HTMLElement>(
      '[data-test-id="tooltip-category-info-target"]',
    );
    if (!target) continue;
    target.dispatchEvent(new MouseEvent('mouseenter', { bubbles: true }));
    await new Promise((resolve) => window.setTimeout(resolve, 100));
    category.description = visibleTooltipText() ?? category.description;
    target.dispatchEvent(new MouseEvent('mouseleave', { bubbles: true }));
  }
  return categories;
}
