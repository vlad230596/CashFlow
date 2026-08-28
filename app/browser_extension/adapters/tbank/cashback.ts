import type { CashbackCategory } from '../types';

export type TbankCashbackCategory = CashbackCategory;

type TbankApiEssence = {
  isActive?: boolean;
  percent?: number;
  name?: string;
  description?: string;
  logo?: string;
  baseColor?: string;
  mccCodes?: string[] | null;
};

type TbankRegularEssences = {
  availableEssenceCount?: number;
  essences?: TbankApiEssence[];
};

type TbankBonusesResponse = {
  payload?: {
    data?: Array<{
      serviceType?: string;
      data?: TbankRegularEssences;
    }>;
  };
};

export type TbankApiCashbackResult = {
  categories: TbankCashbackCategory[];
  maxSelectable: number;
  totalOptions: number;
};

export function extractTbankCashbackFromBonusesResponse(
  response: TbankBonusesResponse,
): TbankApiCashbackResult | null {
  const groups = (response.payload?.data ?? [])
    .filter((item) => item.serviceType === 'regularEssences' && item.data?.essences?.length)
    .map((item) => item.data!);
  const group = groups.sort((left, right) => {
    const active = (items: TbankApiEssence[] = []) => items.filter((item) => item.isActive).length;
    return active(right.essences) - active(left.essences);
  })[0];
  if (!group?.essences?.length) return null;

  const categories = group.essences.flatMap<TbankCashbackCategory>((essence) => {
    if (!essence.name) return [];
    const percent = typeof essence.percent === 'number' ? essence.percent : null;
    return [{
      type: 'standard',
      name: essence.name.replace(/\s+/g, ' ').trim(),
      percent,
      percentLabel: percent == null ? null : `${percent}%`,
      subtitle: essence.mccCodes?.length ? `MCC: ${essence.mccCodes.join(', ')}` : null,
      description: essence.description?.replace(/\s+/g, ' ').trim() || null,
      iconUrl: essence.logo || null,
      iconBackgroundColor: essence.baseColor ? `#${essence.baseColor.replace(/^#/, '')}` : null,
      selected: Boolean(essence.isActive),
      group: 'Повышенный кэшбэк',
      expiresInLabel: null,
    }];
  });
  const selectedCount = categories.filter((category) => category.selected).length;
  return {
    categories,
    maxSelectable: selectedCount + (group.availableEssenceCount ?? 0),
    totalOptions: categories.length,
  };
}

export async function fetchTbankCashbackFromPage(): Promise<TbankApiCashbackResult | null> {
  const nonce = crypto.randomUUID();
  const response = await new Promise<TbankBonusesResponse | null>((resolve) => {
    const timeout = window.setTimeout(() => {
      window.removeEventListener('message', listener);
      resolve(null);
    }, 2500);
    const listener = (event: MessageEvent) => {
      if (
        event.data?.type !== 'cashflow:tbank-bonuses-response' ||
        event.data?.nonce !== nonce
      ) return;
      window.clearTimeout(timeout);
      window.removeEventListener('message', listener);
      resolve(event.data.data as TbankBonusesResponse | null);
    };
    window.addEventListener('message', listener);
    window.postMessage({ type: 'cashflow:tbank-bonuses-request', nonce }, '*');
  });
  return response ? extractTbankCashbackFromBonusesResponse(response) : null;
}

export function parseCashbackCategoryTitle(rawTitle: string): Pick<
  TbankCashbackCategory,
  'name' | 'percent' | 'percentLabel'
> {
  const title = rawTitle.replace(/\s+/g, ' ').trim();
  const match = title.match(/^(\d+(?:[.,]\d+)?)\s*%\s*(.+)$/);

  if (!match) {
    return { name: title, percent: null, percentLabel: null };
  }

  const percent = match[1]!;

  return {
    name: match[2]!,
    percent: Number(percent.replace(',', '.')),
    percentLabel: `${percent}%`,
  };
}

export function extractTbankCashbackCategories(
  root: ParentNode = document,
): TbankCashbackCategory[] {
  const inputs = root.querySelectorAll<HTMLInputElement>(
    'input[data-qa-type="category_checkbox.input"]',
  );
  const items = new Set<HTMLElement>();

  for (const input of inputs) {
    const item = input.closest<HTMLElement>('[data-qa-type="category_item"]');
    if (item) items.add(item);
  }

  for (const item of root.querySelectorAll<HTMLElement>(
    '[data-qa-type="desktop-luca-cashback-select"] [data-qa-type="category_item"]',
  )) {
    items.add(item);
  }

  return [...items].flatMap((item) => {
    const title = item
      ?.querySelector<HTMLElement>('[data-qa-type="category_title.line"]')
      ?.innerText.trim();

    if (!item || !title) return [];

    const parsedTitle = parseCashbackCategoryTitle(title);
    const subtitle = item
      .querySelector<HTMLElement>('[data-qa-type="category_subtitle.line"]')
      ?.innerText.trim();
    const description = item
      .querySelector<HTMLElement>('[data-qa-type="category_tooltip-container"]')
      ?.getAttribute('aria-label')
      ?.trim();
    const icon = item.querySelector<HTMLElement>(
      '[data-qa-type="category_icon"]',
    );
    const iconUrl = item.querySelector<HTMLImageElement>('img')?.src;
    const iconBackgroundColor = icon
      ? getComputedStyle(icon).backgroundColor
      : null;
    const input = item.querySelector<HTMLInputElement>(
      'input[data-qa-type="category_checkbox.input"]',
    );

    return [
      {
        type: 'standard',
        ...parsedTitle,
        subtitle: subtitle || null,
        description: description || null,
        iconUrl: iconUrl || null,
        iconBackgroundColor: iconBackgroundColor || null,
        selected: input ? input.checked : true,
        group: null,
        expiresInLabel: null,
      },
    ];
  });
}
