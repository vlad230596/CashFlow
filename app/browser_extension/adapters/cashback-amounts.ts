/** Shared monetary conditions. Arbitrary prices and discount caps are not cashback limits. */
export function extractCashbackAmounts(text: string | null | undefined): {
  maxCashbackAmount: number | null;
  minPurchaseAmount: number | null;
} {
  const amount = String.raw`(\d[\d\s\u00a0\u202f]*(?:[.,]\d+)?)`;
  const currency = String.raw`(?:₽|руб(?:ль|ля|лей)?\.?|р\.)`;
  const maxPatterns = [
    String.raw`к[еэ]шб[еэ]к\s+до\s+${amount}\s*${currency}`,
    String.raw`лимит\s+к[еэ]шб[еэ]ка[^\d]{0,40}${amount}\s*${currency}`,
    String.raw`максимальн(?:ый|ая|ое)\s+(?:размер\s+|сумма\s+)?к[еэ]шб[еэ]к(?:а)?[^\d]{0,20}${amount}\s*${currency}`,
    String.raw`к[еэ]шб[еэ]к(?:а)?\s+(?:не\s+более|максимум)\s+${amount}\s*${currency}`,
    String.raw`не\s+более\s+${amount}\s*${currency}\s+к[еэ]шб[еэ]к(?:а)?`,
  ];
  const minPatterns = [
    String.raw`(?:покупк[а-яё]*|заказ[а-яё]*|чек[а-яё]*)[^.\n]{0,60}?\s(?:от|не\s+менее)\s+${amount}\s*${currency}`,
    String.raw`минимальн[а-яё]*\s+(?:сумм[а-яё]*|чек[а-яё]*)[^\d]{0,30}${amount}\s*${currency}`,
  ];
  const firstAmount = (patterns: string[]) => {
    for (const pattern of patterns) {
      const match = (text ?? '').match(new RegExp(pattern, 'iu'));
      if (!match?.[1]) continue;
      const value = Number(match[1].replace(/[\s\u00a0\u202f]/g, '').replace(',', '.'));
      if (Number.isFinite(value)) return value;
    }
    return null;
  };
  return { maxCashbackAmount: firstAmount(maxPatterns), minPurchaseAmount: firstAmount(minPatterns) };
}
