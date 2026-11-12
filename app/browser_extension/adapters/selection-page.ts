import type { BankId } from './types';

/**
 * Pages on which the user chooses monthly categories. A navigation, reload or
 * click on such a page throws away a half-made choice, so collection only
 * reads them (see `ProbeSource.isSelectionPage`).
 */
export function isCategorySelectionPage(
  bankId: BankId,
  url: string,
  root: ParentNode = document,
): boolean {
  let path = '';
  try {
    const parsed = new URL(url);
    // Sber routes inside the hash of /CSAFront/index.do.
    path = `${parsed.pathname}${parsed.hash.replace(/^#/, '')}`;
  } catch {
    return false;
  }
  switch (bankId) {
    case 'tbank':
      return path.includes('/high-cashback/offer/');
    case 'sber':
      return path.includes('/loyalty/main/categories/select');
    case 'vtb':
      return /\/bonus\/categories\/?$/.test(path) ||
        Boolean(root.querySelector('input[type="checkbox"][data-test-id^="checked_"]'));
    case 'alfa':
      return Boolean(root.querySelector('input[data-test-id^="checkbox-select-cashback-"]'));
    case 'ozon':
      // The same route shows either the editable choice or the saved list;
      // both are left untouched.
      return path.startsWith('/lk/favorite-categories');
    case 'yandex':
      return false;
  }
}

export function currentPageIsSelection(bankId: BankId): boolean {
  return isCategorySelectionPage(bankId, window.location.href, document);
}
