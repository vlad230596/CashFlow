import type { ExtendedBankResult, ExtendedOffer } from './types';

/** Offers collected longer ago than this are neither shown nor exported. */
export const EXTENDED_MAX_AGE_MS = 24 * 60 * 60 * 1000;

export type ExtendedFreshness =
  | { state: 'missing' }
  | { state: 'stale'; collectedAt: Date; age: string }
  | { state: 'failed'; collectedAt: Date; age: string; error: string | null }
  | {
    state: 'fresh';
    collectedAt: Date;
    age: string;
    /** `running` is reported only while this panel is collecting the bank. */
    run: 'running' | 'interrupted' | 'partial' | 'complete' | 'unknown';
    offers: ExtendedOffer[];
  };

export function ageLabel(ms: number): string {
  const minutes = Math.floor(Math.max(ms, 0) / 60_000);
  if (minutes < 1) return 'только что';
  if (minutes < 60) return `${minutes} мин назад`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} ч назад`;
  return `${Math.floor(hours / 24)} дн назад`;
}

/** Offers the bank listed during the run; history may also hold older ones kept for detail reuse. */
export function currentOffers(result: ExtendedBankResult): ExtendedOffer[] {
  if (!result.catalogIds) return result.offers;
  const listed = new Set(result.catalogIds);
  return result.offers.filter((offer) => listed.has(offer.id));
}

export function extendedFreshness(
  result: ExtendedBankResult | undefined,
  now: Date,
  collectingNow = false,
): ExtendedFreshness {
  const collectedAt = result ? new Date(result.collectedAt) : null;
  if (!result || !collectedAt || Number.isNaN(collectedAt.getTime())) return { state: 'missing' };
  const ageMs = now.getTime() - collectedAt.getTime();
  const age = ageLabel(ageMs);
  if (result.runStatus === 'failed') {
    return { state: 'failed', collectedAt, age, error: result.errors[0] ?? null };
  }
  if (ageMs > EXTENDED_MAX_AGE_MS) return { state: 'stale', collectedAt, age };
  const run = result.runStatus === 'running'
    ? (collectingNow ? 'running' : 'interrupted')
    : result.runStatus ?? 'unknown';
  return { state: 'fresh', collectedAt, age, run, offers: currentOffers(result) };
}
