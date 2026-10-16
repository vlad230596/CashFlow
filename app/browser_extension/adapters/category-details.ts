import type { BankId, CashbackCategory } from './types';
import { withCategoryIcon } from './category-icon';

export { extractCashbackAmounts } from './cashback-amounts';
import { extractCashbackAmounts } from './cashback-amounts';

export function cleanVtbDescription(description: string | null): string | null {
  if (!description) return null;

  const cleaned = description
    .replace(
      /к[еэ]шб[еэ]к\s+до\s+\d[\d\s\u00a0\u202f]*(?:[.,]\d+)?\s*(?:₽|руб(?:ль|ля|лей)?\.?)\s*/giu,
      '',
    )
    .replace(
      /МСС\s*[—–-]\s*это\s+код\s+вида\s+деятельности\s+продавца\.\s*По\s+нему\s+банк\s+определяет\s+категорию\s+покупки\s+для\s+расчета\s+кешбэка\.?\s*/giu,
      '',
    )
    .split(/\n+/)
    .map((line) => line.replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .join('\n');

  return cleaned || null;
}

export function enrichCashbackCategory(
  bankId: BankId,
  category: CashbackCategory,
): CashbackCategory {
  const sourceText = `${category.subtitle ?? ''}\n${category.description ?? ''}`;
  const extracted = extractCashbackAmounts(sourceText);

  return withCategoryIcon(bankId, {
    ...category,
    description:
      bankId === 'vtb' ? cleanVtbDescription(category.description) : category.description,
    maxCashbackAmount: category.maxCashbackAmount ?? extracted.maxCashbackAmount,
    minPurchaseAmount: category.minPurchaseAmount ?? extracted.minPurchaseAmount,
  });
}
