import type {
  AuthenticationStatus,
  BankId,
  CashbackCategory,
  CashbackSelection,
  PageProbe,
} from './types';
import { enrichCashbackCategory } from './category-details';

function normalizedPageText(root: ParentNode): string {
  const documentText = (root as Document).documentElement?.textContent;
  return (documentText ?? root.textContent ?? '').replace(/\s+/g, ' ').trim();
}

export async function preparePageForParsing(): Promise<void> {
  const scrollingElement = document.scrollingElement;
  if (!scrollingElement || scrollingElement.scrollHeight <= scrollingElement.clientHeight) return;

  const initialTop = scrollingElement.scrollTop;
  let previousHeight = 0;
  for (let attempt = 0; attempt < 8; attempt += 1) {
    scrollingElement.scrollTo({ top: scrollingElement.scrollHeight, behavior: 'auto' });
    await new Promise((resolve) => window.setTimeout(resolve, 120));
    if (scrollingElement.scrollHeight === previousHeight) break;
    previousHeight = scrollingElement.scrollHeight;
  }
  scrollingElement.scrollTo({ top: initialTop, behavior: 'auto' });
}

export function extractSelection(
  categories: CashbackCategory[],
  root: ParentNode = document,
): CashbackSelection {
  const text = normalizedPageText(root);
  let maxSelectable: number | null = null;
  let totalOptions: number | null = null;

  const chooseFrom = text.match(
    /(?:выбрать|выберите|можно выбрать)\s+(\d+)\s+(?:категори\S*\s+)?из\s+(\d+)/i,
  );
  const choose = text.match(
    /(?:выбрать|выберите|можно выбрать)\s+(\d+)\s+категори/i,
  );
  if (chooseFrom) {
    maxSelectable = Number(chooseFrom[1]);
    totalOptions = Number(chooseFrom[2]);
  } else if (choose) {
    maxSelectable = Number(choose[1]);
  }
  if (maxSelectable != null && totalOptions == null && categories.length > 0) {
    totalOptions = categories.length;
  }

  const groups = [...new Set(categories.map((category) => category.group).filter(Boolean))] as string[];
  return {
    // The generic parser cannot yet distinguish a saved bank choice from an
    // editable full selection. Bank-specific adapters can override this.
    isLocked: null,
    selectedCount: categories.filter((category) => category.selected).length,
    visibleCount: categories.length,
    maxSelectable,
    totalOptions,
    groups,
  };
}

export function detectAuthenticationStatus(
  bankId: BankId,
  categories: CashbackCategory[],
  url = window.location.href,
  root: ParentNode = document,
): AuthenticationStatus {
  if (categories.length > 0) return 'authenticated';

  const lowerUrl = url.toLowerCase();
  const text = normalizedPageText(root).toLowerCase();
  const loginUrl =
    /\/login|\/signin|passport\.yandex|private\.auth\.alfabank|\/passport\/|\/csafront\/index\.do(?:#\/?)?$/.test(lowerUrl) ||
    (bankId === 'ozon' && lowerUrl.includes('/apps/auth'));
  const loginPage =
    loginUrl ||
    /вход|авторизация/i.test(document.title) ||
    (/войти|вход в/.test(text) &&
      Boolean(root.querySelector('input[type="password"], input[type="tel"]')));

  return loginPage ? 'authentication_required' : 'unknown';
}

export function buildPageProbe(
  bankId: BankId,
  categories: CashbackCategory[],
): PageProbe {
  const enrichedCategories = categories.map((category) =>
    enrichCashbackCategory(bankId, category),
  );
  return {
    bankId,
    title: document.title,
    url: window.location.href,
    readyState: document.readyState,
    authenticationStatus: detectAuthenticationStatus(bankId, enrichedCategories),
    selection: extractSelection(enrichedCategories),
    categories: enrichedCategories,
  };
}
