import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

// Builds one account-scoped document accepted by both production import
// endpoints. The output stays under .local and must never be committed.
const cashbackPath = resolve(
  process.argv[2] ?? '.local/live-bank-confirmation-snapshot.json',
);
const offersPath = resolve(
  process.argv[3] ?? 'assets/partner_offers/offers.json',
);
const outputPath = resolve(
  process.argv[4] ?? '.local/release-recovery-import.json',
);
const cashback = JSON.parse(await readFile(cashbackPath, 'utf8'));
const offers = JSON.parse(await readFile(offersPath, 'utf8'));
const banks = new Map(cashback.banks.map((bank) => [bank.bankId, { ...bank }]));

for (const offer of offers.offers) {
  const bank = banks.get(offer.bankId) ?? {
    bankId: offer.bankId,
    collectionStatus: 'ready',
    authenticationStatus: 'authenticated',
    collectedAt: offer.collectedAt,
    categories: [],
  };
  bank.extendedOffers ??= [];
  const normalized = { ...offer };
  delete normalized.bankId;
  delete normalized.bankName;
  delete normalized.iconAsset;
  for (const key of ['startDate', 'endDate']) {
    if (normalized[key] != null && !/^\d{4}-\d{2}-\d{2}(?:T|$)/.test(normalized[key])) {
      normalized[key] = null;
    }
  }
  bank.extendedOffers.push(normalized);
  bank.extendedSummary = {
    collectedAt: offer.collectedAt,
    previewCount: bank.extendedOffers.length,
    errors: [],
  };
  banks.set(offer.bankId, bank);
}

const document = {
  schemaVersion: 1,
  generatedAt: cashback.generatedAt,
  requestedBanks: cashback.requestedBanks,
  banks: [...banks.values()],
};
await mkdir(dirname(outputPath), { recursive: true });
await writeFile(outputPath, `${JSON.stringify(document, null, 2)}\n`);
console.log(JSON.stringify({
  outputPath,
  categories: document.banks.reduce(
    (total, bank) => total + (bank.categories?.length ?? 0),
    0,
  ),
  confirmedCategories: document.banks.reduce(
    (total, bank) => total + (bank.categories?.filter(
      (category) => category.confirmed === true,
    ).length ?? 0),
    0,
  ),
  offers: document.banks.reduce(
    (total, bank) => total + (bank.extendedOffers?.length ?? 0),
    0,
  ),
}));
