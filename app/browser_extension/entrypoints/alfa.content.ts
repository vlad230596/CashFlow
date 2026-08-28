import { buildPageProbe } from '../adapters/page-probe';
import { extractAlfaCashbackCategoriesWithDetails } from '../adapters/alfa/cashback';
import type { PageProbe } from '../adapters/types';

type PageProbeRequest = { type: 'cashflow:probe-page' };

export default defineContentScript({
  matches: ['https://web.alfabank.ru/*', 'https://private.auth.alfabank.ru/*'],
  runAt: 'document_idle',
  main() {
    browser.runtime.onMessage.addListener(
      async (message: PageProbeRequest): Promise<PageProbe | undefined> => {
        if (message.type !== 'cashflow:probe-page') return undefined;
        if (!document.querySelector('[data-test-id="chosen-category-item"]')) {
          const title = [...document.querySelectorAll<HTMLElement>(
            '[data-test-id="cashback-programs-item-title"]',
          )].find((element) => /^Категории\s+в\s+/i.test(element.textContent?.trim() ?? ''));
          title?.click();
          return buildPageProbe('alfa', []);
        }
        return buildPageProbe(
          'alfa',
          await extractAlfaCashbackCategoriesWithDetails(),
        );
      },
    );
  },
});
