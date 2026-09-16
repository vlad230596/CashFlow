import type { BankId } from '../types';
import { clean, moneyFrom, percentFrom } from './core';
import type { OfferDetail, OfferPreview } from './types';

export function tbankSectionButtons(): HTMLElement[] {
  return [...document.querySelectorAll<HTMLElement>('[data-qa-type^="desktop-bonuses-all-categories-category-"]')]
    .filter(button => /^desktop-bonuses-all-categories-category-[a-z0-9_]+$/i.test(button.getAttribute('data-qa-type') || ''));
}

// Sber's modern routes are client-side: reloading a deep link returns to home.
export async function navigateSberOfferPage(url: string): Promise<boolean> {
  const target = new URL(url);
  if (target.origin !== location.origin || !/^\/app\/loyalty\/main\/(partners|offers|partner|offer)$/.test(target.pathname)) {
    throw new Error('Неизвестный маршрут предложений Сбера');
  }
  const list = target.pathname.endsWith('/partner') ? 'partners'
    : target.pathname.endsWith('/offer') ? 'offers' : target.pathname.split('/').at(-1)!;
  for (let attempt = 0; attempt < 40; attempt++) {
    const current = new URL(location.href);
    if (current.pathname === target.pathname && current.search === target.search) return true;
    const dialog = [...document.querySelectorAll('[role="dialog"]')].at(-1);
    const close = [...(dialog?.querySelectorAll<HTMLElement>('button') ?? [])].find(b => b.innerText.trim() === 'Понятно');
    if (close) close.click();
    else if (current.pathname.endsWith(`/${list}`)) {
      const anchor = [...document.querySelectorAll<HTMLAnchorElement>('main a[href]')]
        .find(a => { const href = new URL(a.href, location.href); return href.pathname === target.pathname && href.search === target.search; });
      anchor?.click();
    } else if (current.pathname.endsWith('/main')) {
      const button = [...document.querySelectorAll<HTMLElement>('main button')]
        .find(b => list === 'partners' ? b.innerText.includes('Магазины и сервисы') : b.getAttribute('aria-label') === 'Акции');
      button?.click();
    } else {
      const back = document.querySelector<HTMLElement>('main button[aria-label="Вернуться назад"]');
      const home = [...document.querySelectorAll<HTMLAnchorElement>('a[href]')]
        .find(a => a.getAttribute('href') === '/app/loyalty/main');
      (back ?? home)?.click();
    }
    await new Promise(resolve => setTimeout(resolve, 350));
  }
  throw new Error(`Не открыт раздел Сбера ${target.pathname}`);
}

const text = (node: Element | null | undefined) => clean((node as HTMLElement | null)?.innerText ?? node?.textContent);
const image = (node: Element | null | undefined) => {
  const element = node as HTMLImageElement | null;
  return element?.currentSrc || element?.src || null;
};
const cssImage = (node: Element | null | undefined) => {
  if (!node) return null;
  const value = getComputedStyle(node).backgroundImage;
  return value.match(/^url\(["']?(.*?)["']?\)$/)?.[1] || null;
};
const absolute = (value: string | null | undefined, base = location.href) => {
  if (!value) return null;
  try { return new URL(value, base).href; } catch { return null; }
};
const links = (root: ParentNode): OfferDetail['links'] =>
  [...root.querySelectorAll<HTMLAnchorElement>('a[href]')].map((anchor) => ({
    text: text(anchor) || anchor.getAttribute('aria-label') || '',
    url: anchor.href,
  })).filter((link) => /^https?:/.test(link.url));
const idFrom = (value: string) => value.toLocaleLowerCase('ru-RU').replace(/[^a-zа-яё0-9]+/giu, '-').replace(/^-|-$/g, '').slice(0, 100);
const rate = (value: string | null) => value?.match(/(?:до\s*)?\d+(?:[.,]\d+)?\s*%/i)?.[0] || null;
const wait = (ms: number) => new Promise((resolve) => window.setTimeout(resolve, ms));

async function waitFor<T>(fn: () => T | null | undefined, label: string, attempts = 60): Promise<T> {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const result = fn();
    if (result) return result;
    await wait(100);
  }
  throw new Error(`Не удалось открыть ${label}`);
}

function preview(bankId: BankId, input: Partial<OfferPreview> & Pick<OfferPreview, 'id' | 'name'>): OfferPreview {
  return {
    bankId, id: input.id, name: input.name,
    offerKind: input.offerKind ?? (/скидк/i.test(`${input.name} ${input.rateLabel || ''} ${input.previewText || ''}`)
      ? 'discount' : /к[еэ]шб[еэ]к|%|бонус/i.test(`${input.name} ${input.rateLabel || ''} ${input.previewText || ''}`)
        ? 'cashback' : 'other'),
    percent: input.percent ?? percentFrom(input.rateLabel), rateLabel: input.rateLabel ?? null,
    startDate: input.startDate ?? null, endDate: input.endDate ?? null,
    expirationLabel: input.expirationLabel ?? null,
    previewConditions: input.previewConditions ?? null,
    previewText: input.previewText ?? null, group: input.group ?? null,
    sourceUrl: input.sourceUrl ?? location.href, detailUrl: input.detailUrl ?? null,
    iconUrl: input.iconUrl ?? null, artworkUrl: input.artworkUrl ?? null,
    selected: input.selected ?? null, canOpenSafely: input.canOpenSafely ?? true,
  };
}

function yandexPreviews(): OfferPreview[] {
  const grid = [...document.querySelectorAll<HTMLElement>('div')].find((element) =>
    element.className?.includes?.('grid-cols-2') && element.querySelectorAll(':scope > div.w-full').length > 10);
  if (!grid) return [];
  return [...grid.children].flatMap((card) => {
    const paragraphs = [...card.querySelectorAll('p')].map(text);
    const name = paragraphs[0];
    const rateLabel = rate(text(card));
    if (!name || !rateLabel) return [];
    const deeplink = card.querySelector<HTMLAnchorElement>('a[aria-label]')?.href || null;
    const merchantUrl = deeplink ? new URL(deeplink).searchParams.get('url') : null;
    const iconUrl = cssImage(card.querySelector('[class*="RoundPicture-module__"][style*="background-image"]'));
    return [preview('yandex', {
      id: idFrom(`${name}-${merchantUrl || deeplink || ''}`), name, rateLabel,
      previewConditions: paragraphs[1], previewText: text(card),
      detailUrl: null, iconUrl,
      artworkUrl: cssImage(card.querySelector('[aria-hidden="true"][style*="background-image"]')),
      canOpenSafely: false,
    })];
  });
}

function ozonPreviews(): OfferPreview[] {
  return [...document.querySelectorAll<HTMLElement>('[data-testid="go-to-promotion-block"]')].flatMap((card) => {
    const name = text(card.querySelector('.card-body-text .title'));
    if (!name) return [];
    const rateLabel = text(card.querySelector('.percent'));
    const connected = /подключено/i.test(text(card.querySelector('[data-testid="activate-promo"]')) || '');
    return [preview('ozon', {
      id: idFrom(`${name}-${text(card.querySelector('.card-body-text .category')) || ''}`),
      name, rateLabel, group: text(card.querySelector('.card-body-text .category')),
      expirationLabel: text(card.querySelector('.badge')),
      previewConditions: text(card.querySelector('.image-text .description')),
      previewText: text(card), iconUrl: image(card.querySelector('img')) || cssImage(card.querySelector('.card-body .logo .image')),
      selected: connected, canOpenSafely: true,
    })];
  });
}

function sberPreviews(): OfferPreview[] {
  const anchors = document.querySelectorAll<HTMLAnchorElement>('main a[href*="/app/loyalty/main/partner?id="], main a[href*="/app/loyalty/main/offer?id="]');
  return [...anchors].flatMap((anchor) => {
    const url = new URL(anchor.href);
    const id = url.searchParams.get('id');
    const name = text(anchor.querySelector('img')) || anchor.querySelector('img')?.alt || text(anchor)?.split('\n')[0];
    if (!id || !name) return [];
    return [preview('sber', {
      id: `${url.pathname.endsWith('/offer') ? 'promotion' : 'partner'}-${id}`,
      name, rateLabel: rate(text(anchor)), previewText: text(anchor),
      detailUrl: url.href, iconUrl: image(anchor.querySelector('img')),
      group: url.pathname.endsWith('/offer') ? 'Акции' : 'Партнёры',
    })];
  });
}

function tbankPreviews(): OfferPreview[] {
  return [...document.querySelectorAll<HTMLElement>('[data-qa-type^="desktop-bonuses-category-list-offer-"]')]
    .filter((card) => /^desktop-bonuses-category-list-offer-\d+$/.test(card.getAttribute('data-qa-type') || ''))
    .flatMap((card) => {
      const label = text(card);
      if (!label) return [];
      const name = text(card.querySelector('h3,h4,h5,h6')) || label.split('\n')[0]!;
      const anchor = card.querySelector<HTMLAnchorElement>('a[href]');
      return [preview('tbank', {
        id: anchor?.href || idFrom(`${name}-${label}`), name,
        rateLabel: rate(label), previewText: label,
        expirationLabel: text(card.querySelector('[class*="expiration"]')),
        detailUrl: anchor?.href || null,
        iconUrl: image(card.querySelector('img')),
        group: text(document.querySelector('[data-qa-type="desktop-bonuses-category-list"] h1')),
      })];
    });
}

function alfaPreviews(): OfferPreview[] {
  return [...document.querySelectorAll<HTMLElement>('[role="dialog"] [data-test-id="offers-selection-body"] button[data-test-id="offer"]')]
    .flatMap((card) => {
      const lines = (card.innerText || '').split('\n').map(clean).filter((line): line is string => !!line);
      const name = lines[0];
      if (!name) return [];
      return [preview('alfa', {
        id: idFrom(`${name}-${lines.join('|')}`), name,
        rateLabel: rate(text(card)), previewText: text(card),
        previewConditions: lines.slice(1).join(' | ') || null,
        iconUrl: image(card.querySelector('img')),
        group: text(document.querySelector('[role="dialog"] [data-test-id="side-panel-header-title"]')),
      })];
    });
}

function vtbBenefitPreviews(): OfferPreview[] {
  const headings = [...document.querySelectorAll<HTMLElement>('h2,h3')];
  const result: OfferPreview[] = [];
  for (const heading of headings) {
    const group = text(heading);
    if (group !== 'От партнеров ВТБ' && group !== 'Еще больше выгоды' && group !== 'Ещё больше выгоды') continue;
    const section = group === 'От партнеров ВТБ' ? heading.parentElement : heading.parentElement?.parentElement;
    for (const card of section?.querySelectorAll<HTMLElement>('[role="button"]') || []) {
      const lines = (card.innerText || '').split('\n').map(clean).filter((line): line is string => !!line);
      const name = lines[0];
      if (!name || (group !== 'От партнеров ВТБ' && !/яндекс|путешеств/i.test(lines.join(' ')))) continue;
      result.push(preview('vtb', {
        id: idFrom(`benefit-${name}`), name, group,
        rateLabel: rate(text(card)), previewConditions: lines[1] || null,
        previewText: text(card), iconUrl: cssImage(card) || image(card.querySelector('img')),
        canOpenSafely: group === 'От партнеров ВТБ',
      }));
    }
  }
  return result;
}

type VtbElement = { elementId?: string; value?: string; urlImage?: string; link?: { url?: string }; arrayData?: VtbElement[]; elementType?: string };
type VtbProduct = { productCode?: string; elements?: VtbElement[] };
type VtbCategory = { categoryCode?: string; elements?: VtbElement[]; products?: VtbProduct[] };
type VtbRaw = { locations?: Array<{ locationName?: string; positions?: Array<{ positionName?: string; categories?: VtbCategory[] }> }> };
const element = (items: VtbElement[] | undefined, id: string) => items?.find((item) => item.elementId === id);
const detailed = (items: VtbElement[] | undefined, prefix: string) => items?.find((item) => item.elementId?.startsWith(`detailedPage-${prefix}-`));

export async function vtbCatalogue(captured?: VtbRaw | null): Promise<Array<{ preview: OfferPreview; detail: OfferDetail }>> {
  let raw = captured;
  if (!raw) {
    const response = await fetch('/msa/api-gw/private/dsls/dsls-content-category/v1/categories', { credentials: 'include' });
    if (!response.ok) throw new Error(`Каталог ВТБ: HTTP ${response.status}`);
    raw = await response.json() as VtbRaw;
  }
  const categories = raw.locations?.find((item) => item.locationName === 'CASHBACK_PAGE')
    ?.positions?.find((item) => item.positionName === 'CATEGORY')?.categories;
  if (!categories?.length) throw new Error('Каталог ВТБ не содержит категорий');
  const offers = new Map<string, { preview: OfferPreview; detail: OfferDetail }>();
  for (const category of categories) {
    const group = clean(element(category.elements, 'heading')?.value);
    for (const product of category.products || []) {
      const id = product.productCode;
      const name = clean(element(product.elements, 'heading')?.value);
      if (!id || !name) continue;
      const data = element(product.elements, 'detailedPage')?.arrayData;
      const conditions = detailed(data, 'description')?.value?.trim() || null;
      const rateLabel = clean(element(product.elements, 'description')?.value);
      const current = offers.get(id);
      const previewData = preview('vtb', {
        id: `catalogue-${id}`, name, rateLabel, group,
        previewConditions: rateLabel, previewText: `${name} ${rateLabel || ''}`,
        iconUrl: absolute(element(product.elements, 'image')?.urlImage, 'https://h2.sbpvtb.ru'),
        artworkUrl: absolute(data?.find((item) => item.elementType === 'IMAGE')?.urlImage, 'https://h2.sbpvtb.ru'),
        detailUrl: absolute(element(product.elements, 'body')?.link?.url),
      });
      if (current) {
        if (current.preview.name !== previewData.name || current.preview.rateLabel !== previewData.rateLabel ||
          current.preview.iconUrl !== previewData.iconUrl || current.detail.conditions !== conditions) {
          throw new Error(`Противоречивые данные предложения ВТБ: ${id}`);
        }
        current.preview.group = [...new Set([current.preview.group, group].filter(Boolean))].sort().join(', ');
        continue;
      }
      offers.set(id, { preview: previewData, detail: {
        description: clean(detailed(data, 'heading')?.value), conditions,
        steps: [], links: [
          { text: 'Правила', url: detailed(data, 'secondaryButton')?.link?.url || '' },
          { text: 'Покупки', url: detailed(data, 'primaryButton')?.link?.url || '' },
        ].filter((link) => !!link.url),
        maxCashbackAmount: null, minPurchaseAmount: null,
      } });
    }
  }
  return [...offers.values()];
}

export function scanPreviews(bankId: BankId): OfferPreview[] {
  switch (bankId) {
    case 'yandex': return yandexPreviews();
    case 'ozon': return ozonPreviews();
    case 'sber': return sberPreviews();
    case 'tbank': return tbankPreviews();
    case 'alfa': return alfaPreviews();
    case 'vtb': return vtbBenefitPreviews();
  }
}

export async function readDetail(bankId: BankId, item: OfferPreview): Promise<OfferDetail> {
  if (bankId === 'yandex') {
    const legal = document.querySelector<HTMLElement>('[data-test-id="globalCashbackCalculated:legal"]');
    return { description: item.previewConditions, conditions: text(legal), steps: [],
      links: legal ? links(legal) : [], maxCashbackAmount: null, minPurchaseAmount: null };
  }
  if (bankId === 'sber') {
    await waitFor(() => document.querySelector<HTMLElement>('main section'), 'условия Сбера');
    const root = document.querySelector<HTMLElement>('main')!;
    const isPartnerPage = /\/loyalty\/main\/partner(?:\?|$)/.test(location.href);
    const closeDialog = async () => {
      for (let attempt = 0; attempt < 12; attempt++) {
        const dialog = [...document.querySelectorAll<HTMLElement>('[role="dialog"]')].at(-1);
        const button = [...(dialog?.querySelectorAll<HTMLElement>('button') || [])]
          .find((item) => text(item) === 'Понятно');
        if (!button) return;
        button.click();
        await wait(50);
      }
    };
    if (isPartnerPage) {
      for (let attempt = 0; attempt < 15; attempt++) {
        const button = [...root.querySelectorAll<HTMLElement>('button')].find((item) => text(item) === 'Показать ещё');
        if (!button) break;
        button.click();
        await wait(100);
      }
    }
    let fullConditions: string | null = null;
    const showAll = isPartnerPage
      ? [...root.querySelectorAll<HTMLElement>('button')].find((item) => text(item) === 'Показать все')
      : null;
    if (showAll) {
      showAll.click();
      const dialog = await waitFor(() => [...document.querySelectorAll<HTMLElement>('[role="dialog"]')]
        .find((item) => /Условия партнёра|Условия партнера/i.test(item.innerText)), 'полные условия Сбера');
      fullConditions = text(dialog);
      await closeDialog();
    }
    const steps: string[] = [];
    const rateButtons = [...root.querySelectorAll<HTMLElement>('button')]
      .filter((button) => /Показать подробнее/i.test(text(button) || ''));
    for (const button of rateButtons) {
      button.click();
      const dialog = await waitFor(() => [...document.querySelectorAll<HTMLElement>('[role="dialog"]')]
        .find((item) => /Понятно/.test(item.innerText)), 'подробности ставки Сбера');
      const value = text(dialog);
      if (value) steps.push(value);
      await closeDialog();
    }
    const full = root.innerText.replace(/^Назад\s*/, '').trim();
    return { description: full, conditions: [full, fullConditions].filter(Boolean).join('\n\n'), steps, links: links(root),
      maxCashbackAmount: null, minPurchaseAmount: null };
  }
  if (bankId === 'ozon') {
    const root = await waitFor(() => document.querySelector<HTMLElement>('[data-testid="promotion-container"] [data-testid="hero-block-description"]')
      ?.closest<HTMLElement>('[data-testid="promotion-container"]'), 'условия Ozon');
    const content = root.querySelector<HTMLElement>(':scope > .content');
    const recommendations = root.querySelector<HTMLElement>('[data-testid="same-promotions-section"]');
    const recommendationUrls = new Set([...recommendations?.querySelectorAll<HTMLAnchorElement>('a[href]') || []]
      .map((anchor) => anchor.href));
    const all = content?.innerText.split(recommendations?.innerText || '\u0000')[0]?.trim() || root.innerText;
    return {
      description: text(root.querySelector('[data-testid="about-section"]')),
      conditions: all, steps: [text(root.querySelector('[data-testid="how-to-section"]'))].filter((x): x is string => !!x),
      links: links(root).filter((link) => !recommendationUrls.has(link.url)),
      maxCashbackAmount: null, minPurchaseAmount: null,
    };
  }
  if (bankId === 'tbank') {
    const root = await waitFor(() => document.querySelector<HTMLElement>('[data-qa-type="desktop-bonuses-offer"]'), 'условия Т-Банка');
    const steps = [...root.querySelectorAll<HTMLElement>('[data-qa-type^="desktop-bonuses-offer-steps__step-"], [data-qa-type^="desktop-bonuses-receipt-steps__step"]')]
      .map(text).filter((x): x is string => !!x);
    const conditions = [
      text(root.querySelector('[data-qa-type="desktop-bonuses-offer-card"]')),
      text(root.querySelector('[data-qa-type="desktop-bonuses-offer-expiration"]')),
      text(root.querySelector('[data-qa-type*="other-conditions"]')),
    ].filter(Boolean).join('\n\n') || text(root);
    return { description: [
      text(root.querySelector('[data-qa-type="desktop-bonuses-partner-info-description"]')),
      text(root.querySelector('[data-qa-type="desktop-bonuses-offer-product-info-skeleton-description"]')),
    ].filter(Boolean).join('\n\n') || null,
      conditions, steps, links: links(root), maxCashbackAmount: null, minPurchaseAmount: null };
  }
  if (bankId === 'vtb') {
    const root = document.querySelector<HTMLElement>('.omega-ui-retail__bottom-sheet');
    if (!root) throw new Error('Не найдены условия ВТБ');
    return { description: null, conditions: text(root), steps: [], links: links(root),
      maxCashbackAmount: null, minPurchaseAmount: null };
  }
  const root = document.querySelector<HTMLElement>('[role="dialog"] [data-test-id="offer-details-body"]');
  if (!root) throw new Error('Не найдены условия Альфа-Банка');
  return { description: text(root.querySelector('[data-test-id="partner-description"]'))
      || text(root.querySelector('[data-test-id="offer-details-short-description"]')),
    conditions: [
      text(root.querySelector('[data-test-id="offer-webview-description"]')),
      ...[...root.querySelectorAll<HTMLElement>('[data-test-id="condition"]')].map(text),
    ].filter(Boolean).join('\n') || text(root),
    steps: [...root.querySelectorAll<HTMLElement>('[data-test-id="offer-details-steps"] [data-test-id="cell"]')]
      .map(text).filter((x): x is string => !!x), links: links(root),
    maxCashbackAmount: moneyFrom(text(root.querySelector('[data-test-id*="limit"]'))),
    minPurchaseAmount: moneyFrom(text(root.querySelector('[data-test-id*="minimum"]'))),
  };
}

export async function openInlineDetail(
  bankId: BankId, item: OfferPreview,
  enrich?: (detail: OfferDetail) => Promise<OfferDetail>,
): Promise<OfferDetail> {
  const cards = () => bankId === 'alfa'
    ? [...document.querySelectorAll<HTMLElement>('[role="dialog"] [data-test-id="offers-selection-body"] button[data-test-id="offer"]')]
    : bankId === 'vtb'
      ? [...document.querySelectorAll<HTMLElement>('[role="button"]')]
      : [...document.querySelectorAll<HTMLElement>('[data-qa-type^="desktop-bonuses-category-list-offer-"]')];
  const findTarget = () => cards().find((card) => {
    const label = text(card);
    return label && (label === item.previewText || label.includes(item.name));
  });
  let target = findTarget();
  if (!target && bankId === 'tbank') {
    const height = document.documentElement.scrollHeight;
    const step = Math.max(400, Math.floor(window.innerHeight * 0.6));
    for (let y = 0; y <= height && !target; y += step) {
      window.scrollTo({ top: y, behavior: 'instant' });
      window.dispatchEvent(new Event('scroll'));
      await wait(180);
      target = findTarget();
    }
  }
  if (!target) throw new Error(`Карточка ${item.name} исчезла из списка`);
  target.click();
  if (bankId === 'alfa') await waitFor(() => document.querySelector('[role="dialog"] [data-test-id="offer-details-body"]'), item.name);
  else if (bankId === 'vtb') await waitFor(() => document.querySelector('.omega-ui-retail__bottom-sheet'), item.name);
  else await waitFor(() => document.querySelector('[data-qa-type="desktop-bonuses-offer"]'), item.name);
  const rawDetail = await readDetail(bankId, item);
  const detail = enrich ? await enrich(rawDetail) : rawDetail;
  if (bankId === 'alfa') document.querySelector<HTMLElement>('[role="dialog"] [data-test-id="side-panel-header-back"]')?.click();
  if (bankId === 'vtb') document.querySelector<HTMLElement>('.omega-ui-retail__bottom-sheet [aria-label="Закрыть окно"]')?.click();
  return detail;
}
