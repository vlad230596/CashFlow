import {
  extractTbankCashbackCategories,
  fetchTbankCashbackFromPage,
  type TbankApiCashbackResult,
} from '../adapters/tbank/cashback';
import { registerProbeListener } from '../adapters/probe-runner';
import { currentPageIsSelection } from '../adapters/selection-page';

export default defineContentScript({
  matches: ['https://www.tbank.ru/*', 'https://id.tbank.ru/*'],
  runAt: 'document_idle',
  main() {
    let api: TbankApiCashbackResult | null = null;
    let apiCheckedAt = 0;
    registerProbeListener({
      bankId: 'tbank',
      async read() {
        // The bridge answers from the page's latest bonuses response (or one
        // API request when there is none); refresh it at most every 2 s.
        if (Date.now() - apiCheckedAt > 2000) {
          apiCheckedAt = Date.now();
          api = await fetchTbankCashbackFromPage();
        }
        // The offer page is where categories are chosen: its checkboxes show
        // an unsaved choice, so only the bank's API answer is used there. The
        // page used to be left for /mybank/bonuses/ by a reload on every
        // automatic probe, which threw away the owner's half-made choice.
        if (currentPageIsSelection('tbank')) return api?.categories ?? [];
        return api?.categories ?? extractTbankCashbackCategories();
      },
      isSelectionPage: () => currentPageIsSelection('tbank'),
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
