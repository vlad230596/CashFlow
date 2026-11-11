import { enrichOzonDescriptions, extractOzonCashbackCategories } from '../adapters/ozon/cashback';
import { registerProbeListener } from '../adapters/probe-runner';

export default defineContentScript({
  matches: ['https://finance.ozon.ru/*'],
  runAt: 'document_idle',
  main() {
    // Each detail sheet is opened once per page load; later probes reuse the
    // text instead of flashing every sheet on every automatic cycle.
    const descriptions = new Map<string, string>();
    registerProbeListener({
      bankId: 'ozon',
      read: () => extractOzonCashbackCategories(),
      advance: (collected) => {
        if (collected.length) return false;
        const button = document.querySelector<HTMLElement>('[data-testid="cashback-in-current-month-banner"] button');
        button?.click();
        return Boolean(button);
      },
      enrich: (categories) => enrichOzonDescriptions(categories, descriptions),
      scrollLazyContent: true,
    });
  },
});
