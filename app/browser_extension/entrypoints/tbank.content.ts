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
      (message: PageProbeRequest): Promise<PageProbe> | undefined => {
        if (message.type !== 'cashflow:probe-page') return undefined;
        return (async () => {

        const domCategories = extractTbankCashbackCategories();

        if (window.location.pathname.includes('/high-cashback/offer/')) {
          window.location.assign('/mybank/bonuses/');
          return buildPageProbe('tbank', []);
        }

        const apiResult = await fetchTbankCashbackFromPage();
        const probe = buildPageProbe('tbank', apiResult?.categories ?? domCategories);
        if (apiResult) {
          probe.selection.maxSelectable = apiResult.maxSelectable;
          probe.selection.totalOptions = apiResult.totalOptions;
        }
        return probe;
        })();
      },
    );
  },
});
