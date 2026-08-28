export type CashbackCategory = {
  type: 'standard' | 'stackable_bonus';
  name: string;
  percent: number | null;
  percentLabel: string | null;
  subtitle: string | null;
  description: string | null;
  iconUrl: string | null;
  iconBackgroundColor: string | null;
  selected: boolean;
  group: string | null;
  expiresInLabel: string | null;
  maxCashbackAmount?: number | null;
  minPurchaseAmount?: number | null;
};

export type BankId = 'tbank' | 'yandex' | 'alfa' | 'sber' | 'ozon' | 'vtb';

export type AuthenticationStatus =
  | 'authenticated'
  | 'authentication_required'
  | 'unknown';

export type CashbackSelection = {
  isLocked: boolean | null;
  selectedCount: number;
  visibleCount: number;
  maxSelectable: number | null;
  totalOptions: number | null;
  groups: string[];
};

export type PageProbe = {
  bankId: BankId;
  title: string;
  url: string;
  readyState: DocumentReadyState;
  authenticationStatus: AuthenticationStatus;
  selection: CashbackSelection;
  categories: CashbackCategory[];
};

export type CollectionStatus = 'waiting' | 'collecting' | 'ready' | 'auth' | 'error';

export type CashbackImportBankResult = {
  bankId: BankId;
  bankName: string;
  collectionStatus: CollectionStatus;
  collectedAt: string | null;
  title: string | null;
  url: string | null;
  readyState: DocumentReadyState | null;
  authenticationStatus: AuthenticationStatus;
  selection: CashbackSelection;
  categories: CashbackCategory[];
  message: string | null;
};

export type CashbackImportDocument = {
  schemaVersion: 1;
  generatedAt: string;
  requestedBanks: BankId[];
  banks: CashbackImportBankResult[];
};
