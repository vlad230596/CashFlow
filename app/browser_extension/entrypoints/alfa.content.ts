import {
  enrichAlfaDescriptions,
  extractAlfaCashbackCategories,
  hasAlfaCategoryList,
  openAlfaCategoryProgram,
} from '../adapters/alfa/cashback';
import { registerProbeListener } from '../adapters/probe-runner';

export default defineContentScript({
  matches: ['https://web.alfabank.ru/*', 'https://private.auth.alfabank.ru/*'],
  runAt: 'document_idle',
  main() {
    registerProbeListener({
      bankId: 'alfa',
      // The program summary also shows stackable bonuses; categories are read
      // only once the monthly list itself is open.
      read: () => hasAlfaCategoryList() ? extractAlfaCashbackCategories() : [],
      advance: (collected) => !collected.length && openAlfaCategoryProgram(),
      enrich: (categories) => enrichAlfaDescriptions(categories),
      scrollLazyContent: true,
    });
  },
});
