import { extractYandexCashbackCategories } from '../adapters/yandex/cashback';
import { buildPageProbe } from '../adapters/page-probe';
import type { PageProbe } from '../adapters/types';

type PageProbeRequest = {
  type: 'cashflow:probe-page';
};

export default defineContentScript({
  matches: ['https://bank.yandex.ru/*', 'https://sp.yandex.ru/*'],
  runAt: 'document_idle',
  main() {
    browser.runtime.onMessage.addListener(
      async (message: PageProbeRequest): Promise<PageProbe | undefined> => {
        if (message.type !== 'cashflow:probe-page') return undefined;

        return buildPageProbe('yandex', extractYandexCashbackCategories());
      },
    );
  },
});
