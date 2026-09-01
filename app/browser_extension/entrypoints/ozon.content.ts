import { extractOzonCashbackCategoriesWithDetails } from '../adapters/ozon/cashback';
import { buildPageProbe } from '../adapters/page-probe';
import type { PageProbe } from '../adapters/types';

type PageProbeRequest = {
  type: 'cashflow:probe-page';
};

export default defineContentScript({
  matches: ['https://finance.ozon.ru/*'],
  runAt: 'document_idle',
  main() {
    browser.runtime.onMessage.addListener(
      async (message: PageProbeRequest): Promise<PageProbe | undefined> => {
        if (message.type !== 'cashflow:probe-page') return undefined;

        const categories = await extractOzonCashbackCategoriesWithDetails();
        if (categories.length) return buildPageProbe('ozon', categories);

        const cashbackButton = document.querySelector<HTMLElement>(
          '[data-testid="cashback-in-current-month-banner"] button',
        );
        cashbackButton?.click();
        return buildPageProbe('ozon', []);
      },
    );
  },
});
