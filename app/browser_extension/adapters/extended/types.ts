import type { BankId } from '../types';

export type OfferPreview = {
  bankId: BankId;
  id: string;
  name: string;
  offerKind: 'cashback' | 'discount' | 'other';
  percent: number | null;
  rateLabel: string | null;
  startDate: string | null;
  endDate: string | null;
  expirationLabel: string | null;
  previewConditions: string | null;
  previewText: string | null;
  group: string | null;
  sourceUrl: string;
  detailUrl: string | null;
  iconUrl: string | null;
  artworkUrl: string | null;
  selected: boolean | null;
  canOpenSafely: boolean;
};

export type ExtendedOffer = OfferPreview & {
  type: 'partner_offer';
  description: string | null;
  conditions: string | null;
  steps: string[];
  links: Array<{ text: string; url: string }>;
  maxCashbackAmount: number | null;
  minPurchaseAmount: number | null;
  detailsStatus: 'complete' | 'preview_only' | 'error';
  detailsError: string | null;
  previewFingerprint: string;
  detailCollectedAt: string | null;
};

export type OfferDetail = Pick<ExtendedOffer,
  'description' | 'conditions' | 'steps' | 'links' | 'maxCashbackAmount' | 'minPurchaseAmount'>;

export type ExtendedBankResult = {
  bankId: BankId;
  collectedAt: string;
  sourceUrls: string[];
  offers: ExtendedOffer[];
  previewCount: number;
  reusedCount: number;
  openedCount: number;
  previewOnlyCount: number;
  errors: string[];
};
