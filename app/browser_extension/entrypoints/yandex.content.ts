import { expandYandexCategories, extractYandexCashbackCategories } from '../adapters/yandex/cashback';
import { registerProbeListener } from '../adapters/probe-runner';

export default defineContentScript({
  matches: ['https://bank.yandex.ru/*', 'https://sp.yandex.ru/*'],
  runAt: 'document_idle',
  main() {
    registerProbeListener({
      bankId: 'yandex',
      read: () => extractYandexCashbackCategories(),
      // «Ещё N категорий» only expands the list in place.
      expand: () => expandYandexCategories(),
      scrollLazyContent: true,
    });
  },
});
