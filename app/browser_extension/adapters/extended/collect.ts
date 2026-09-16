import type { BankId } from '../types';
import { findBank } from '../../banks/registry';
import { createOffer, reuseOffer, uniquePreviews } from './core';
import type { ExtendedBankResult, ExtendedOffer, OfferDetail, OfferPreview } from './types';

const routes: Record<BankId, string[]> = {
  tbank: ['https://www.tbank.ru/mybank/bonuses/category/all/'],
  yandex: ['https://bank.yandex.ru/webview-sdk/partners/cashback'],
  alfa: ['https://web.alfabank.ru/partner-offers/'],
  sber: [
    'https://online.sberbank.ru/app/loyalty/main/partners',
    'https://online.sberbank.ru/app/loyalty/main/offers',
  ],
  ozon: ['https://finance.ozon.ru/lk/promotions?filter=all'],
  vtb: [
    'https://online.sbpvtb.ru/products/cashback/catalogue',
    'https://online.sbpvtb.ru/bonus',
  ],
};

type Message = Record<string, unknown> & { type: string };
const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const historyKey = (bankId: BankId) => `cashflowExtendedHistory:${bankId}`;

async function send<T>(tabId: number, message: Message, attempts = 20): Promise<T> {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try { return await browser.tabs.sendMessage(tabId, message) as T; }
    catch (error) { lastError = error; await sleep(250); }
  }
  throw lastError;
}

async function navigate(tabId: number, url: string) {
  const tab = await browser.tabs.get(tabId);
  if (url.startsWith('https://online.sberbank.ru/app/loyalty/main/')) {
    await browser.tabs.update(tabId, { active: true });
    await send(tabId, { type: 'cashflow:extended-sber-navigate', url }, 1);
    await sleep(350);
    return;
  }
  await browser.tabs.update(tabId, tab.url !== url ? { url, active: true } : { active: true });
  const target = new URL(url);
  const routePath = (value: URL) => (value.hash.startsWith('#/app/') ? value.hash.slice(1).split('?')[0]! : value.pathname)
    .replace(/\/$/, '');
  for (let attempt = 0; attempt < 80; attempt++) {
    const current = await browser.tabs.get(tabId);
    const actual = current.url ? new URL(current.url) : null;
    if (current.status === 'complete' && actual?.origin === target.origin && routePath(actual) === routePath(target)) {
      await sleep(350);
      return;
    }
    await sleep(150);
  }
  throw new Error(`Не загрузилась страница ${url}`);
}

async function scan(tabId: number, bankId: BankId, attempts = 30): Promise<OfferPreview[]> {
  let previews: OfferPreview[] = [];
  for (let attempt = 0; attempt < attempts; attempt++) {
    previews = await send<OfferPreview[]>(tabId, { type: 'cashflow:extended-scan', bankId });
    if (previews.length) return previews;
    await sleep(200);
  }
  return previews;
}

function storageResult(bankId: BankId, value: unknown): ExtendedBankResult | null {
  if (!value || typeof value !== 'object') return null;
  const result = value as ExtendedBankResult;
  return result.bankId === bankId && Array.isArray(result.offers) ? result : null;
}

export async function collectExtendedBank(
  bankId: BankId,
  progress?: (value: ExtendedBankResult) => void,
): Promise<ExtendedBankResult> {
  const previous = storageResult(bankId, (await browser.storage.local.get(historyKey(bankId)))[historyKey(bankId)]);
  const old = new Map(previous?.offers.map((offer) => [offer.id, offer]) || []);
  const result: ExtendedBankResult = {
    bankId, collectedAt: new Date().toISOString(), sourceUrls: [], offers: [],
    previewCount: 0, reusedCount: 0, openedCount: 0, previewOnlyCount: 0, errors: [],
  };
  const tabs = await browser.tabs.query({ url: findBank(bankId).tabPatterns });
  const preferredOrigin = new URL(routes[bankId][0]!).origin;
  const usable = tabs.filter((item) => item.id != null && !/\/login|\/signin|\/auth\//i.test(item.url || ''));
  const tab = usable.find((item) => item.url?.startsWith(preferredOrigin)) ?? usable[0];
  if (!tab?.id) throw new Error(`Откройте и авторизуйте вкладку: ${findBank(bankId).name}`);
  const tabId = tab.id;
  const previewMap = new Map<string, OfferPreview>();
  const embeddedDetails = new Map<string, OfferDetail>();

  const add = (items: OfferPreview[]) => {
    for (const item of items) {
      const prior = previewMap.get(item.id);
      if (prior) {
        item.group = [...new Set([prior.group, item.group].filter(Boolean))].join(', ') || null;
      }
      previewMap.set(item.id, item);
    }
  };
  const save = async () => {
    result.collectedAt = new Date().toISOString();
    result.previewCount = previewMap.size;
    result.previewOnlyCount = result.offers.filter((offer) => offer.detailsStatus === 'preview_only').length;
    const merged = new Map(previous?.offers.map((offer) => [offer.id, offer]) || []);
    for (const offer of result.offers) merged.set(offer.id, offer);
    await browser.storage.local.set({ [historyKey(bankId)]: { ...result, offers: [...merged.values()] } });
    progress?.({ ...result, offers: [...result.offers], errors: [...result.errors] });
  };

  for (const route of routes[bankId]) {
    try {
      await navigate(tabId, route);
      result.sourceUrls.push(route);
      if (bankId === 'vtb' && route.includes('/catalogue')) {
        const items = await send<Array<{ preview: OfferPreview; detail: OfferDetail }>>(tabId, { type: 'cashflow:extended-vtb-catalogue' });
        for (const item of items) { add([item.preview]); embeddedDetails.set(item.preview.id, item.detail); }
      } else if (bankId === 'tbank') {
        const sections = await send<Array<{ name: string; expectedCount: number | null }>>(tabId, { type: 'cashflow:extended-tbank-sections' });
        for (let index = 0; index < sections.length; index++) {
          await navigate(tabId, route);
          try { await send(tabId, { type: 'cashflow:extended-tbank-open-section', index }, 1); }
          catch { /* A full page navigation can close the message channel. */ }
          for (let attempt = 0; attempt < 40; attempt++) {
            const current = await browser.tabs.get(tabId);
            if (current.url?.includes('/bonuses/categories/')) break;
            await sleep(150);
          }
          const cards = await scan(tabId, bankId);
          const section = sections[index]!;
          if (section.expectedCount != null && cards.length !== section.expectedCount) {
            result.errors.push(`${section.name}: собрано ${cards.length} из ${section.expectedCount}`);
          }
          add(cards.map((card) => ({ ...card, group: section.name || card.group })));
        }
      } else if (bankId === 'alfa') {
        const categories = await send<Array<{ name: string; expectedCount: number }>>(tabId, { type: 'cashflow:extended-alfa-categories' });
        for (const category of categories) {
          if (category.expectedCount === 0) continue;
          const cards = await send<OfferPreview[]>(tabId, { type: 'cashflow:extended-alfa-select-category', name: category.name });
          if (cards.length !== category.expectedCount) {
            result.errors.push(`${category.name}: собрано ${cards.length} из ${category.expectedCount}`);
          }
          add(cards.map((card) => ({ ...card, group: category.name })));
        }
      } else {
        add(await scan(tabId, bankId));
      }
    } catch (error) {
      result.errors.push(`${route}: ${String(error)}`);
    }
    await save();
  }

  // Details are visited only after the complete preview catalogue has been read.
  // This allows the previous snapshot to be compared before any card is opened.
  const previews = uniquePreviews([...previewMap.values()]);
  if (!previews.length) throw new Error(result.errors.join('; ') || `Каталог ${findBank(bankId).name} пуст или недоступен`);
  for (const item of previews) {
    const reused = reuseOffer(item, old.get(item.id));
    if (reused) {
      result.offers.push(reused);
      result.reusedCount++;
      await save();
      continue;
    }
    const embedded = embeddedDetails.get(item.id);
    if (embedded) {
      result.offers.push(createOffer(item, embedded, 'complete'));
      await save();
      continue;
    }
    if (bankId === 'yandex') {
      try {
        const programTab = (await browser.tabs.query({ url: 'https://sp.yandex.ru/cashback*' }))[0];
        const detail = programTab?.id != null
          ? await send<OfferDetail>(programTab.id, { type: 'cashflow:extended-detail', bankId, offer: item })
          : null;
        result.offers.push(createOffer(item, detail, detail?.conditions ? 'complete' : 'preview_only',
          detail?.conditions ? null : 'Не открыта страница общих условий Яндекс Пэй'));
      } catch (error) {
        result.offers.push(createOffer(item, null, 'error', String(error)));
      }
      await save();
      continue;
    }
    if (!item.canOpenSafely) {
      result.offers.push(createOffer(item, null, 'preview_only',
        'На странице нет безопасного просмотра условий'));
      await save();
      continue;
    }
    try {
      let detail: OfferDetail;
      if (item.detailUrl) {
        await navigate(tabId, item.detailUrl);
        detail = await send<OfferDetail>(tabId, { type: 'cashflow:extended-detail', bankId, offer: item });
      } else if (bankId === 'ozon') {
        await navigate(tabId, routes.ozon[0]!);
        const current = await scan(tabId, bankId);
        const index = current.findIndex((offer) => offer.id === item.id);
        if (index < 0) throw new Error('Акция исчезла из списка');
        const clicked = await send<boolean>(tabId, { type: 'cashflow:extended-open-ozon', index }, 1).catch(() => true);
        if (!clicked) throw new Error('Не удалось открыть акцию');
        for (let attempt = 0; attempt < 40; attempt++) {
          if ((await browser.tabs.get(tabId)).url?.includes('/lk/promotion?')) break;
          await sleep(150);
        }
        detail = await send<OfferDetail>(tabId, { type: 'cashflow:extended-detail', bankId, offer: item });
      } else {
        const listRoute = bankId === 'vtb' ? routes.vtb[1]! : bankId === 'tbank' ? item.sourceUrl : routes.alfa[0]!;
        await navigate(tabId, listRoute);
        if (bankId === 'alfa') {
          await send(tabId, { type: 'cashflow:extended-alfa-categories' });
          await send(tabId, { type: 'cashflow:extended-alfa-select-category', name: item.group?.split(', ')[0] || '' });
        }
        try {
          detail = await send<OfferDetail>(tabId, { type: 'cashflow:extended-detail', bankId, offer: item, inline: true }, 1);
        } catch (error) {
          if (bankId !== 'tbank') throw error;
          for (let attempt = 0; attempt < 40; attempt++) {
            if ((await browser.tabs.get(tabId)).url?.includes('/bonuses/offers/')) break;
            await sleep(150);
          }
          detail = await send<OfferDetail>(tabId, { type: 'cashflow:extended-detail', bankId, offer: item });
        }
      }
      result.offers.push(createOffer(item, detail, 'complete'));
      result.openedCount++;
    } catch (error) {
      result.offers.push(createOffer(item, null, 'error', String(error)));
      result.errors.push(`${item.name}: ${String(error)}`);
    }
    await save();
  }
  if (!result.errors.length) await browser.storage.local.set({ [historyKey(bankId)]: result });
  return result;
}
