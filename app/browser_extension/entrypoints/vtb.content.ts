import { extractVtbCashbackCategories } from '../adapters/vtb/cashback';
import { registerProbeListener } from '../adapters/probe-runner';
import { currentPageIsSelection } from '../adapters/selection-page';

export default defineContentScript({
  matches: ['https://online.sbpvtb.ru/*'],
  runAt: 'document_idle',
  main() {
    registerProbeListener({
      bankId: 'vtb',
      // Reading the category cards is deliberately passive: opening every
      // "Подробнее" modal on each automatic cycle made the VTB page flash.
      read: () => extractVtbCashbackCategories(),
      advance: (collected) => {
        if (collected.length) return false;
        let control: HTMLElement | null | undefined = null;
        if (window.location.pathname === '/home') {
          control = document.querySelector<HTMLElement>('[data-test-id="morebenefits_favorite-buttons"]');
        } else if (window.location.pathname === '/bonus') {
          control = document.querySelector<HTMLElement>('[aria-label^="Выберите категории кешбэка"]') ??
            [...document.querySelectorAll<HTMLElement>('button, [role="button"]')]
              .find((element) => /^(?:Посмотреть категории кешбэка|Выберите категории кешбэка)/i.test(
                element.innerText.replace(/\s+/g, ' ').trim(),
              ));
        }
        control?.click();
        return Boolean(control);
      },
      isSelectionPage: () => currentPageIsSelection('vtb'),
      scrollLazyContent: true,
    });
  },
});
