import type { BankId, CashbackCategory } from './types';
import { withCategoryIcon } from './category-icon';

function amountFromMatch(match: RegExpMatchArray | null): number | null {
  if (!match?.[1]) return null;
  const normalized = match[1].replace(/[\s\u00a0\u202f]/g, '').replace(',', '.');
  const amount = Number(normalized);
  return Number.isFinite(amount) ? amount : null;
}

export function extractCashbackAmounts(text: string): {
  maxCashbackAmount: number | null;
  minPurchaseAmount: number | null;
} {
  const amount = String.raw`(\d[\d\s\u00a0\u202f]*(?:[.,]\d+)?)`;
  const currency = String.raw`(?:₽|руб(?:ль|ля|лей)?\.?|р\.)`;
  const maxPatterns = [
    new RegExp(String.raw`к[еэ]шб[еэ]к\s+до\s+${amount}\s*${currency}`, 'iu'),
    new RegExp(String.raw`лимит\s+к[еэ]шб[еэ]ка[^\d]{0,40}${amount}\s*${currency}`, 'iu'),
  ];
  const minPatterns = [
    new RegExp(
      String.raw`(?:покупк[а-яё]*|заказ[а-яё]*|чек[а-яё]*)[^.\n]{0,60}?\sот\s+${amount}\s*${currency}`,
      'iu',
    ),
    new RegExp(
      String.raw`минимальн[а-яё]*\s+(?:сумм[а-яё]*|чек[а-яё]*)[^\d]{0,30}${amount}\s*${currency}`,
      'iu',
    ),
  ];

  return {
    maxCashbackAmount:
      maxPatterns.map((pattern) => amountFromMatch(text.match(pattern))).find((value) => value != null) ?? null,
    minPurchaseAmount:
      minPatterns.map((pattern) => amountFromMatch(text.match(pattern))).find((value) => value != null) ?? null,
  };
}

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
