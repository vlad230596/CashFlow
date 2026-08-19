import type { CashbackCategory } from '../types';

export type VtbCashbackCategory = CashbackCategory;

type ParsedVtbCategoryTitle = Pick<
  VtbCashbackCategory,
  'name' | 'percent' | 'percentLabel'
>;

function normalizeText(value: string | null | undefined): string {
  return value?.replace(/\s+/g, ' ').trim() ?? '';
}

export function parseVtbCategoryTitle(rawTitle: string): ParsedVtbCategoryTitle | null {
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

function findCategoryItem(input: HTMLInputElement): HTMLElement | null {
  let element = input.parentElement;
  while (element) {
    const inputs = element.querySelectorAll<HTMLInputElement>('input[type="checkbox"]');
    const hasDetails = [...element.querySelectorAll<HTMLButtonElement>('button')].some(
      (button) => normalizeText(button.textContent) === 'Подробнее',
    );
    if (inputs.length === 1 && hasDetails) return element;
    element = element.parentElement;
  }
  return null;
}

function svgToDataUrl(item: HTMLElement): string | null {
  const svg = item.querySelector<SVGSVGElement>('svg');
  if (!svg) return null;

  const clone = svg.cloneNode(true) as SVGSVGElement;
  const originals = [svg, ...svg.querySelectorAll<SVGElement>('*')];
  const clones = [clone, ...clone.querySelectorAll<SVGElement>('*')];
  originals.forEach((original, index) => {
    const target = clones[index];
    if (!target) return;
    if (target.getAttribute('fill')?.includes('var(')) {
      target.setAttribute('fill', getComputedStyle(original).fill);
    }
    if (target.getAttribute('stroke')?.includes('var(')) {
      target.setAttribute('stroke', getComputedStyle(original).stroke);
    }
  });
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(clone.outerHTML)}`;
}

function findGroup(input: HTMLInputElement): string | null {
  const group = input.closest<HTMLElement>('.omega-ui-retail__checkbox-group');
  return normalizeText(group?.previousElementSibling?.textContent) || null;
}

function categoryFromInput(input: HTMLInputElement): VtbCashbackCategory | null {
  const item = findCategoryItem(input);
  if (!item) return null;

  const title = input.id
    ? normalizeText(document.querySelector<HTMLLabelElement>(`label[for="${CSS.escape(input.id)}"]`)?.textContent)
    : '';
  const parsed = parseVtbCategoryTitle(title);
  if (!parsed) return null;

  const lines = [...item.querySelectorAll<HTMLElement>('p, label')]
    .map((element) => normalizeText(element.textContent))
    .filter((line) => line && line !== title && line !== 'Подробнее');
  const subtitle = lines.find((line) => !/^Кешбэк до\s+/i.test(line)) ?? null;
  const descriptionLines = lines.filter((line) => line !== subtitle);
  const ariaLimit = normalizeText(input.getAttribute('aria-label')).match(/Кешбэк до\s+.+$/i)?.[0];
  if (ariaLimit) descriptionLines.push(ariaLimit);

  return {
    type: 'standard',
    ...parsed,
    subtitle,
    description: descriptionLines.length ? [...new Set(descriptionLines)].join('\n') : null,
    iconUrl: svgToDataUrl(item),
    iconBackgroundColor: null,
    selected: input.checked,
    group: findGroup(input),
    expiresInLabel: null,
  };
}

export function extractVtbCashbackCategories(
  root: ParentNode = document,
): VtbCashbackCategory[] {
  const categories: VtbCashbackCategory[] = [];
  for (const input of root.querySelectorAll<HTMLInputElement>(
    'input[type="checkbox"][data-test-id^="checked_"]',
  )) {
    const category = categoryFromInput(input);
    if (category) categories.push(category);
  }
  return categories;
}

function findDetailsRoot(category: VtbCashbackCategory): HTMLElement | null {
  const closeButtons = [
    ...document.querySelectorAll<HTMLButtonElement>(
      '[data-test-id="close_button_modalwindow"]',
    ),
  ].reverse();
  for (const closeButton of closeButtons) {
    const dialog = closeButton.closest<HTMLElement>('[role="dialog"]');
    if (dialog && normalizeText(dialog.textContent).includes(category.name)) return dialog;

    let element = closeButton.parentElement;
    while (element?.parentElement) {
      const text = normalizeText(element.textContent);
      if (text.includes(category.name) && /MCC|МСС|кешбэк|К покупкам/i.test(text)) {
        return element;
      }
      element = element.parentElement;
    }
  }
  return null;
}

function readDetails(category: VtbCashbackCategory): string | null {
  const root = findDetailsRoot(category);
  if (!root) return null;

  const title = `${category.percentLabel} ${category.name}`;
  const excluded = new Set([
    title,
    category.subtitle ?? '',
    'Подробнее',
    'Закрыть',
    'О начислении кешбэка',
  ]);
  const lines = [...root.querySelectorAll<HTMLElement>('p, h1, h2, h3, label')]
    .map((element) => normalizeText(element.textContent))
    .filter((line) => line && !excluded.has(line));
  return lines.length ? [...new Set(lines)].join('\n') : null;
}

function waitForDetails(
  category: VtbCashbackCategory,
  timeoutMs = 1000,
): Promise<string | null> {
  const startedAt = Date.now();
  return new Promise((resolve) => {
    const check = () => {
      const details = readDetails(category);
      if (details || Date.now() - startedAt >= timeoutMs) {
        resolve(details);
        return;
      }
      window.setTimeout(check, 40);
    };
    check();
  });
}

function mergeDescription(current: string | null, details: string | null): string | null {
  const lines = `${current ?? ''}\n${details ?? ''}`
    .split(/\n+/)
    .map(normalizeText)
    .filter(Boolean);
  return lines.length ? [...new Set(lines)].join('\n') : null;
}

function waitForModalToClose(timeoutMs = 800): Promise<void> {
  const startedAt = Date.now();
  return new Promise((resolve) => {
    const check = () => {
      const visibleCloseButton = [
        ...document.querySelectorAll<HTMLElement>(
          '[data-test-id="close_button_modalwindow"]',
        ),
      ].some((element) => {
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0 && getComputedStyle(element).visibility !== 'hidden';
      });
      if (!visibleCloseButton || Date.now() - startedAt >= timeoutMs) {
        resolve();
        return;
      }
      window.setTimeout(check, 40);
    };
    check();
  });
}

export async function extractVtbCashbackCategoriesWithDetails(): Promise<
  VtbCashbackCategory[]
> {
  const categories = extractVtbCashbackCategories();
  const inputs = [
    ...document.querySelectorAll<HTMLInputElement>(
      'input[type="checkbox"][data-test-id^="checked_"]',
    ),
  ];

  for (const [index, category] of categories.entries()) {
    const item = inputs[index] ? findCategoryItem(inputs[index]!) : null;
    const detailsButton = [...(item?.querySelectorAll<HTMLButtonElement>('button') ?? [])].find(
      (button) => normalizeText(button.textContent) === 'Подробнее',
    );
    if (!detailsButton) continue;

    detailsButton.click();
    category.description = mergeDescription(
      category.description,
      await waitForDetails(category),
    );
    document
      .querySelector<HTMLButtonElement>('[data-test-id="close_button_modalwindow"]')
      ?.click();
    await waitForModalToClose();
  }

  return categories;
}
