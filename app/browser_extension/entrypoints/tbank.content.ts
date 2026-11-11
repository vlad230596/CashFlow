import {
  extractTbankCashbackCategories,
  fetchTbankCashbackFromPage,
  type TbankApiCashbackResult,
} from '../adapters/tbank/cashback';
import { registerProbeListener } from '../adapters/probe-runner';

export default defineContentScript({
  matches: ['https://www.tbank.ru/*', 'https://id.tbank.ru/*'],
  runAt: 'document_idle',
  main() {
    let api: TbankApiCashbackResult | null = null;
    let apiCheckedAt = 0;
    registerProbeListener({
      bankId: 'tbank',
      async read() {
        if (window.location.pathname.includes('/high-cashback/offer/')) return [];
        // The bridge answers from the page's latest bonuses response (or one
        // API request when there is none); refresh it at most every 2 s.
        if (Date.now() - apiCheckedAt > 2000) {
          apiCheckedAt = Date.now();
          api = await fetchTbankCashbackFromPage();
        }
        return api?.categories ?? extractTbankCashbackCategories();
      },
      advance: () => {
        if (!window.location.pathname.includes('/high-cashback/offer/')) return false;
        window.location.assign('/mybank/bonuses/');
        return true;
      },
      finish(probe) {
        if (api && probe.categories.length) {
          probe.selection.maxSelectable = api.maxSelectable;
          probe.selection.totalOptions = api.totalOptions;
        }
        return probe;
      },
    });
  },
});
