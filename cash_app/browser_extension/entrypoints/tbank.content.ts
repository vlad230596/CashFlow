import {
  extractTbankCashbackCategories,
  fetchTbankCashbackFromPage,
} from '../adapters/tbank/cashback';
import { buildPageProbe } from '../adapters/page-probe';
import type { PageProbe } from '../adapters/types';

type PageProbeRequest = {
  type: 'cashflow:probe-page';
};

export default defineContentScript({
  matches: ['https://www.tbank.ru/*', 'https://id.tbank.ru/*'],
  runAt: 'document_idle',
  main() {
    browser.runtime.onMessage.addListener(
      async (message: PageProbeRequest): Promise<PageProbe | undefined> => {
        if (message.type !== 'cashflow:probe-page') return undefined;

        const domCategories = extractTbankCashbackCategories();
        if (domCategories.length) return buildPageProbe('tbank', domCategories);

        if (window.location.pathname.includes('/high-cashback/offer/')) {
          window.location.assign('/mybank/bonuses/');
          return buildPageProbe('tbank', []);
        }

        const apiResult = await fetchTbankCashbackFromPage();
        const probe = buildPageProbe('tbank', apiResult?.categories ?? []);
        if (apiResult) {
          probe.selection.maxSelectable = apiResult.maxSelectable;
          probe.selection.totalOptions = apiResult.totalOptions;
        }
        return probe;
      },
    );
  },
});
