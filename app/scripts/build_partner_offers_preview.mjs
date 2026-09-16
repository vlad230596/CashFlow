import { mkdir, readFile, readdir, copyFile, writeFile } from 'node:fs/promises';
import { resolve, join, extname } from 'node:path';
import { offerMetadata } from './lib/partner-offer-preview.mjs';

// Run from app/: node scripts/build_partner_offers_preview.mjs [source-directory]
const source = resolve(process.argv[2] ?? '.local');
const target = resolve('assets/partner_offers');
await mkdir(join(target, 'icons'), { recursive: true });
const names = { tbank: 'Т-Банк', alfa: 'Альфа-Банк', sber: 'Сбер', ozon: 'Ozon Банк', yandex: 'Яндекс Пэй', vtb: 'ВТБ' };
const offers = new Map();
const freshSignatures = new Map();
const sources = [];
const iconCache = JSON.parse(await readFile(join(source, 'partner-offer-icons.json'), 'utf8').catch(() => '{}'));
const documents = await Promise.all((await readdir(source)).filter(f => f.endsWith('partner-offers.json')).map(async file => {
  const document = JSON.parse(await readFile(join(source, file), 'utf8'));
  const timestamp = Math.max(0, ...(document.banks ?? [document]).map(bank => Date.parse(bank.extendedSummary?.collectedAt ?? bank.collectedAt ?? '') || 0));
  return { file, document, timestamp };
}));
const history = documents.flatMap(({ document }) => (document.banks ?? [document]).flatMap(bank =>
  (bank.extendedOffers ?? [...(bank.offers ?? []), ...(bank.unclassifiedOffers ?? []), ...(bank.partners ?? []), ...(bank.promotions ?? []), ...(bank.stores ?? [])]).map(raw => ({ raw, bank }))));
for (const { file, document } of documents.sort((a, b) => b.timestamp - a.timestamp || a.file.localeCompare(b.file))) {
  const banks = document.banks ?? [document];
  for (const bank of banks) {
    sources.push({ file, bankId: bank.bankId, collectedAt: bank.extendedSummary?.collectedAt ?? bank.collectedAt ?? null });
    const records = bank.extendedOffers ?? [...(bank.offers ?? []), ...(bank.unclassifiedOffers ?? []), ...(bank.partners ?? []), ...(bank.promotions ?? []), ...(bank.stores ?? [])];
    for (const [index, raw] of records.entries()) {
      const details = raw.details ?? {};
      const name = raw.name ?? raw.partnerName ?? raw.title ?? 'Предложение';
      const older = history.filter(value => value.raw !== raw && value.bank.bankId === bank.bankId
        && (value.raw.id === raw.id && raw.id != null || (value.raw.name ?? value.raw.partnerName ?? value.raw.title) === name && value.raw.rateLabel === raw.rateLabel))
        .sort((a, b) => (Date.parse(b.bank.collectedAt) || 0) - (Date.parse(a.bank.collectedAt) || 0));
      const id = String(raw.id ?? details.alias ?? raw.detailPath ?? `${name}-${index}`);
      const key = `${bank.bankId}:${id}`;
      if (offers.has(key)) continue;
      const rateLabel = raw.rateLabel ?? raw.cashbackLabel ?? (raw.title?.includes('%') ? raw.title : null) ?? raw.cardText?.match(/[^\n]*\d+[,.]?\d*\s*%[^\n]*/)?.[0] ?? null;
      const percent = raw.percent ?? Number(rateLabel?.match(/(\d+(?:[,.]\d+)?)\s*%/)?.[1]?.replace(',', '.') ?? NaN);
      const signature = `${bank.bankId}:${name.trim().toLocaleLowerCase('ru')}:${rateLabel?.replace(/\s+/g, ' ').trim() ?? ''}`;
      if (freshSignatures.has(signature) && freshSignatures.get(signature) !== file) continue;
      freshSignatures.set(signature, file);
      let iconAsset = null;
      const cachedIcon = iconCache[`${bank.bankId}:${name}`];
      const iconFile = cachedIcon?.file ?? raw.iconFile;
      if (iconFile && ['.png', '.jpg', '.jpeg', '.webp', '.gif'].includes(extname(iconFile).toLowerCase())) {
        const iconName = `${bank.bankId}-${iconFile.split('/').at(-1)}`;
        await copyFile(join(source, iconFile), join(target, 'icons', iconName));
        iconAsset = `assets/partner_offers/icons/${iconName}`;
      }
      offers.set(key, {
        id: key, bankId: bank.bankId, bankName: bank.bankName ?? names[bank.bankId] ?? bank.bankId,
        name, rateLabel: rateLabel?.replace(/\s+/g, ' ').trim() ?? null,
        percent: Number.isFinite(percent) ? percent : null,
        description: raw.description ?? raw.partnerDescription ?? details.partnerDescription ?? details.aboutPartner ?? details.shortDescription ?? raw.merchantSubtitle ?? raw.subtitle ?? raw.directoryDescription ?? raw.previewConditions ?? raw.detailsText ?? details.text ?? '',
        iconAsset, iconUrl: cachedIcon?.url ?? raw.iconUrl ?? raw.icon?.value ?? raw.directoryLogoUrl ?? null,
        collectedAt: bank.extendedSummary?.collectedAt ?? bank.collectedAt ?? null,
        expirationLabel: raw.expirationLabel ?? raw.expirationDate ?? null,
        sourceUrl: raw.sourceUrl ?? raw.url ?? bank.sourceUrl ?? null,
        ...offerMetadata(raw, bank, older),
      });
    }
  }
}
await writeFile(join(target, 'offers.json'), JSON.stringify({ schemaVersion: 1, sources, offers: [...offers.values()] }, null, 2) + '\n');
console.log(`Prepared ${offers.size} offers from ${sources.length} sources.`);
