import type { BankId } from '../adapters/types';
import { navigateSberOfferPage, openInlineDetail, readDetail, scanPreviews, tbankSectionButtons, vtbCatalogue } from '../adapters/extended/page';
import type { OfferDetail, OfferPreview } from '../adapters/extended/types';
import { percentFrom } from '../adapters/extended/core';

type Request =
  | { type: 'cashflow:extended-sber-navigate'; url: string }
  | { type: 'cashflow:extended-scan'; bankId: BankId }
  | { type: 'cashflow:extended-detail'; bankId: BankId; offer: OfferPreview; inline?: boolean }
  | { type: 'cashflow:extended-vtb-catalogue' }
  | { type: 'cashflow:extended-tbank-sections' }
  | { type: 'cashflow:extended-tbank-open-section'; index: number }
  | { type: 'cashflow:extended-alfa-categories' }
  | { type: 'cashflow:extended-alfa-select-category'; name: string }
  | { type: 'cashflow:extended-open-ozon'; index: number };

const pause = (ms: number) => new Promise((resolve) => window.setTimeout(resolve, ms));

type PageCard = {
  text: string; id: string; name?: string | null; title?: string | null;
  subtitle?: string | null; expirationLabel?: string | null;
  detailUrl?: string | null; iconUrl?: string | null; artworkUrl?: string | null;
  rateLabel?: string | null; previewConditions?: string | null;
  startDate?: string | null; endDate?: string | null; warningText?: string | null;
};

function pageData<T>(kind: 'tbank-cards' | 'alfa-cards' | 'alfa-rules' | 'vtb-catalogue'): Promise<T | null> {
  const nonce = crypto.randomUUID();
  return new Promise((resolve) => {
    const timeout = window.setTimeout(() => { window.removeEventListener('message', listener); resolve(null); }, 1000);
    const listener = (event: MessageEvent) => {
      if (event.source !== window || event.data?.type !== 'cashflow:extended-main-response' || event.data.nonce !== nonce) return;
      window.clearTimeout(timeout);
      window.removeEventListener('message', listener);
      resolve(event.data.data as T | null);
    };
    window.addEventListener('message', listener);
    window.postMessage({ type: 'cashflow:extended-main-request', kind, nonce }, '*');
  });
}

async function enhancedScan(bankId: BankId): Promise<OfferPreview[]> {
  const previews = scanPreviews(bankId);
  if (bankId !== 'tbank' && bankId !== 'alfa') return previews;
  const cards = await pageData<PageCard[]>(bankId === 'tbank' ? 'tbank-cards' : 'alfa-cards');
  if (!cards?.length) return previews;
  return previews.map((item) => {
    const card = cards.find((candidate) => candidate.text === item.previewText);
    if (!card) return item;
    if (bankId === 'tbank') return {
      ...item, id: card.id, name: card.name || item.name,
      rateLabel: card.title?.match(/(?:до\s*)?\d+(?:[.,]\d+)?\s*%/i)?.[0] || item.rateLabel,
      percent: percentFrom(card.title) ?? item.percent,
      previewConditions: card.subtitle || item.previewConditions,
      startDate: card.startDate || item.startDate,
      endDate: card.endDate || item.endDate,
      expirationLabel: card.expirationLabel || item.expirationLabel,
      detailUrl: card.detailUrl || item.detailUrl,
      iconUrl: card.iconUrl || item.iconUrl, artworkUrl: card.artworkUrl || item.artworkUrl,
    };
    return {
      ...item, id: card.id, name: card.name || item.name,
      rateLabel: card.rateLabel || item.rateLabel,
      percent: percentFrom(card.rateLabel) ?? item.percent,
      previewConditions: card.previewConditions || item.previewConditions,
      startDate: card.startDate || item.startDate,
      endDate: card.endDate || item.endDate,
      expirationLabel: card.warningText || item.expirationLabel,
      iconUrl: card.iconUrl || item.iconUrl,
    };
  });
}

export default defineContentScript({
  matches: [
    'https://www.tbank.ru/*', 'https://bank.yandex.ru/*', 'https://sp.yandex.ru/*',
    'https://web.alfabank.ru/*', 'https://online.sberbank.ru/*',
    'https://finance.ozon.ru/*', 'https://online.sbpvtb.ru/*',
  ],
  runAt: 'document_idle',
  main() {
    browser.runtime.onMessage.addListener((request: Request) => {
      if (!request.type?.startsWith('cashflow:extended-')) return undefined;
      if (request.type === 'cashflow:extended-sber-navigate') return navigateSberOfferPage(request.url);
      return (async () => {
      if (request.type === 'cashflow:extended-scan') {
        if (request.bankId === 'tbank' && location.pathname.includes('/bonuses/categories/')) {
          const found = new Map<string, OfferPreview>();
          const height = document.documentElement.scrollHeight;
          const step = Math.max(400, Math.floor(window.innerHeight * 0.6));
          const oldY = window.scrollY;
          for (let y = 0; y <= height; y += step) {
            window.scrollTo({ top: y, behavior: 'instant' });
            window.dispatchEvent(new Event('scroll'));
            document.dispatchEvent(new Event('scroll'));
            await pause(180);
            for (const item of await enhancedScan('tbank')) found.set(item.id, item);
          }
          window.scrollTo({ top: height, behavior: 'instant' });
          await pause(200);
          for (const item of await enhancedScan('tbank')) found.set(item.id, item);
          window.scrollTo({ top: oldY, behavior: 'instant' });
          return [...found.values()];
        }
        if (request.bankId === 'sber' && location.href.includes('/loyalty/main/partners')) {
          for (let index = 0; index < 30; index++) {
            const button = [...document.querySelectorAll<HTMLElement>('main button')]
              .find((item) => item.innerText.trim() === 'Показать ещё');
            if (!button) break;
            button.click();
            await pause(150);
          }
        }
        return enhancedScan(request.bankId);
      }
      if (request.type === 'cashflow:extended-detail') {
        return request.inline
          ? openInlineDetail(request.bankId, request.offer, async (detail: OfferDetail) => {
            if (request.bankId !== 'alfa') return detail;
            const rulesUrl = await pageData<string>('alfa-rules');
            return rulesUrl ? { ...detail, links: [...detail.links, { text: 'Правила акции', url: rulesUrl }] } : detail;
          })
          : readDetail(request.bankId, request.offer);
      }
      if (request.type === 'cashflow:extended-vtb-catalogue') {
        let captured = await pageData<Parameters<typeof vtbCatalogue>[0]>('vtb-catalogue');
        for (let attempt = 0; !captured && attempt < 25; attempt++) {
          await pause(200);
          captured = await pageData<Parameters<typeof vtbCatalogue>[0]>('vtb-catalogue');
        }
        return vtbCatalogue(captured);
      }
      if (request.type === 'cashflow:extended-tbank-sections') {
        for (let attempt = 0; attempt < 40 && !tbankSectionButtons().length; attempt++) await pause(100);
        const buttons = tbankSectionButtons();
        return buttons.map((button) => ({
          name: button.querySelector('h6')?.textContent?.trim() || button.innerText.trim(),
          expectedCount: Number(button.querySelectorAll('h6')[1]?.textContent) || null,
        }));
      }
      if (request.type === 'cashflow:extended-tbank-open-section') {
        for (let attempt = 0; attempt < 40 && !tbankSectionButtons().length; attempt++) await pause(100);
        const buttons = tbankSectionButtons();
        buttons[request.index]?.click();
        return true;
      }
      if (request.type === 'cashflow:extended-alfa-categories') {
        const all = [...document.querySelectorAll<HTMLElement>('[data-test-id="categories-carousel"] button')]
          .find((button) => button.textContent?.trim() === 'Все категории');
        all?.click();
        for (let attempt = 0; attempt < 40 && !document.querySelector('[role="dialog"] button[data-test-id="category"]'); attempt++) await pause(100);
        return [...document.querySelectorAll<HTMLElement>('[role="dialog"] button[data-test-id="category"]')]
          .map((button) => {
            const lines = button.innerText.split('\n').map((part) => part.trim()).filter(Boolean);
            return { name: lines[0] || '', expectedCount: Number(lines.at(-1)) || 0 };
          }).filter((item) => !!item.name);
      }
      if (request.type === 'cashflow:extended-alfa-select-category') {
        const back = document.querySelector<HTMLElement>('[role="dialog"] button[data-test-id="side-panel-header-back"]');
        back?.click();
        for (let attempt = 0; attempt < 30 && !document.querySelector('[role="dialog"] button[data-test-id="category"]'); attempt++) await pause(100);
        const button = [...document.querySelectorAll<HTMLElement>('[role="dialog"] button[data-test-id="category"]')]
          .find((item) => item.innerText.split('\n')[0]?.trim() === request.name);
        if (!button) throw new Error(`Нет категории ${request.name}`);
        button.click();
        for (let attempt = 0; attempt < 40 && !document.querySelector('[role="dialog"] [data-test-id="offers-selection-body"]'); attempt++) await pause(100);
        return enhancedScan('alfa');
      }
      if (request.type === 'cashflow:extended-open-ozon') {
        const card = [...document.querySelectorAll<HTMLElement>('[data-testid="go-to-promotion-block"]')][request.index];
        if (!card) return false;
        card.click();
        return true;
      }
      return undefined;
      })();
    });
  },
});
