import type { ExtendedOffer, OfferDetail, OfferPreview } from './types';

export function clean(value: string | null | undefined): string | null {
  return value?.replace(/\s+/g, ' ').trim() || null;
}

export function percentFrom(value: string | null | undefined): number | null {
  const match = value?.match(/(\d+(?:[.,]\d+)?)\s*%/);
  return match ? Number(match[1]!.replace(',', '.')) : null;
}

export function moneyFrom(value: string | null | undefined): number | null {
  const match = value?.replace(/\s|\u00a0/g, '').match(/(\d+(?:[.,]\d+)?)\s*(?:₽|руб)/i);
  return match ? Number(match[1]!.replace(',', '.')) : null;
}

function amountAfter(value: string | null | undefined, pattern: RegExp): number | null {
  const match = value?.match(pattern);
  return match ? moneyFrom(match[0]) : null;
}

export function limitsFromConditions(value: string | null | undefined) {
  return {
    maxCashbackAmount: amountAfter(value,
      /(?:максимальн(?:ый|ая|ое)|лимит|не более|до)\s+(?:размер\s+)?(?:к[еэ]шб[еэ]к(?:а)?\s+)?\d[\d\s\u00a0]*(?:[.,]\d+)?\s*(?:₽|руб)/i),
    minPurchaseAmount: amountAfter(value,
      /(?:покупк[аиу]|сумм[ауы]|чек)\s+(?:на\s+сумму\s+)?(?:от|не менее)\s+\d[\d\s\u00a0]*(?:[.,]\d+)?\s*(?:₽|руб)/i),
  };
}

// The key deliberately includes every field visible before opening an offer.
// A missing date/condition is represented explicitly, never inferred from history.
export function previewFingerprint(preview: OfferPreview): string {
  return JSON.stringify([
    preview.bankId, preview.id, clean(preview.name), preview.offerKind, preview.percent,
    clean(preview.rateLabel), clean(preview.startDate), clean(preview.endDate),
    clean(preview.expirationLabel), clean(preview.previewConditions),
    clean(preview.previewText), clean(preview.group), preview.sourceUrl,
    preview.detailUrl, preview.iconUrl, preview.artworkUrl, preview.selected,
  ]);
}

export function reuseOffer(preview: OfferPreview, previous?: ExtendedOffer): ExtendedOffer | null {
  if (!previous || previous.detailsStatus !== 'complete' ||
    previous.previewFingerprint !== previewFingerprint(preview)) return null;
  return { ...previous, ...preview };
}

export function createOffer(
  preview: OfferPreview,
  detail: Partial<OfferDetail> | null,
  detailsStatus: ExtendedOffer['detailsStatus'],
  detailsError: string | null = null,
): ExtendedOffer {
  const limits = limitsFromConditions(detail?.conditions);
  return {
    ...preview,
    type: 'partner_offer',
    description: detail?.description ?? null,
    conditions: detail?.conditions ?? null,
    steps: detail?.steps ?? [],
    links: detail?.links ?? [],
    maxCashbackAmount: detail?.maxCashbackAmount ?? limits.maxCashbackAmount,
    minPurchaseAmount: detail?.minPurchaseAmount ?? limits.minPurchaseAmount,
    detailsStatus,
    detailsError,
    previewFingerprint: previewFingerprint(preview),
    detailCollectedAt: detailsStatus === 'complete' ? new Date().toISOString() : null,
  };
}

export function uniquePreviews(previews: OfferPreview[]): OfferPreview[] {
  const result = new Map<string, OfferPreview>();
  for (const preview of previews) {
    const key = `${preview.bankId}:${preview.id}`;
    const old = result.get(key);
    if (!old) result.set(key, preview);
    else if (previewFingerprint(old) !== previewFingerprint(preview)) {
      const groups = [...new Set([old.group, preview.group].filter(Boolean))].sort().join(', ');
      result.set(key, { ...preview, group: groups || null });
    }
  }
  return [...result.values()];
}
