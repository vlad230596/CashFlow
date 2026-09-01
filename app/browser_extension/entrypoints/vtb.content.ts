import { extractVtbCashbackCategories } from '../adapters/vtb/cashback';
import { buildPageProbe } from '../adapters/page-probe';
import type { PageProbe } from '../adapters/types';

type PageProbeRequest = {
  type: 'cashflow:probe-page';
};

export default defineContentScript({
  matches: ['https://online.sbpvtb.ru/*'],
  runAt: 'document_idle',
  main() {
    browser.runtime.onMessage.addListener(
      async (message: PageProbeRequest): Promise<PageProbe | undefined> => {
        if (message.type !== 'cashflow:probe-page') return undefined;

        // Probes run repeatedly while the side panel is open. Reading the category
        // cards is deliberately passive: opening every "Подробнее" modal here made
        // the VTB page visibly flash on each automatic collection cycle.
        const categories = extractVtbCashbackCategories();
        if (categories.length) return buildPageProbe('vtb', categories);

        if (window.location.pathname === '/home') {
          document.querySelector<HTMLElement>(
            '[data-test-id="morebenefits_favorite-buttons"]',
          )?.click();
        } else if (window.location.pathname === '/bonus') {
          const categoryControl = document.querySelector<HTMLElement>(
            '[aria-label^="Выберите категории кешбэка"]',
          ) ?? [...document.querySelectorAll<HTMLElement>('button, [role="button"]')]
            .find((element) => /^(?:Посмотреть категории кешбэка|Выберите категории кешбэка)/i.test(
              element.innerText.replace(/\s+/g, ' ').trim(),
            ));
          categoryControl?.click();
        }

        return buildPageProbe('vtb', []);
      },
    );
  },
});
