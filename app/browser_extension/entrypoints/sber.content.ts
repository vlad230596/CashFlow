import { extractSberCashbackCategories } from '../adapters/sber/cashback';
import { findSberCategoriesControl, findSberLoyaltyControl } from '../adapters/sber/navigation';
import { registerProbeListener } from '../adapters/probe-runner';

export default defineContentScript({
  matches: ['https://online.sberbank.ru/*'],
  runAt: 'document_idle',
  main() {
    registerProbeListener({
      bankId: 'sber',
      read: () => extractSberCashbackCategories(),
      advance: (collected) => {
        if (collected.length) return false;
        const { hostname, pathname } = window.location;
        let control: HTMLElement | null = null;
        if (hostname === 'online.sberbank.ru' && pathname.startsWith('/app/') && !pathname.includes('/loyalty/')) {
          control = findSberLoyaltyControl();
        } else if (pathname === '/app/loyalty/main' || pathname === '/app/loyalty/main/categories') {
          control = findSberCategoriesControl();
        }
        control?.click();
        return Boolean(control);
      },
      scrollLazyContent: true,
    });
  },
});
