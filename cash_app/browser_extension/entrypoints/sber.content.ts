import { extractSberCashbackCategories } from '../adapters/sber/cashback';
import { buildPageProbe } from '../adapters/page-probe';
import {
  findSberCategoriesControl,
  findSberLoyaltyControl,
} from '../adapters/sber/navigation';
import type { PageProbe } from '../adapters/types';

type PageProbeRequest = {
  type: 'cashflow:probe-page';
};

export default defineContentScript({
  matches: ['https://online.sberbank.ru/*'],
  runAt: 'document_idle',
  main() {
    browser.runtime.onMessage.addListener(
      async (message: PageProbeRequest): Promise<PageProbe | undefined> => {
        if (message.type !== 'cashflow:probe-page') return undefined;

        const categories = extractSberCashbackCategories();
        if (categories.length) return buildPageProbe('sber', categories);

        if (
          window.location.hostname === 'online.sberbank.ru' &&
          window.location.pathname.startsWith('/app/') &&
          !window.location.pathname.includes('/loyalty/')
        ) {
          findSberLoyaltyControl()?.click();
        } else if (
          window.location.pathname === '/app/loyalty/main' ||
          window.location.pathname === '/app/loyalty/main/categories'
        ) {
          findSberCategoriesControl()?.click();
        }

        return buildPageProbe('sber', []);
      },
    );
  },
});
