const clean = value => typeof value === 'string' ? value.replace(/\s+/g, ' ').trim() : '';
const texts = values => [...new Set(values.flat(Infinity).filter(value => typeof value === 'string' && value.trim()).map(value => value.trim()))];

export function offerConditions(raw) {
  const details = raw.details ?? {};
  return texts([
    raw.conditions, raw.otherConditions, raw.detailsText,
    details.fullConditions, details.terms, details.conditions, details.howTo,
    details.text, raw.steps ?? [], details.steps ?? [],
    (details.rateDetails ?? []).map(value => value.text),
  ]).join('\n\n');
}

function statements(value) {
  const lines = value.split(/\n+|\s+(?=Максимальн|К[еэ]шб[еэ]к (?:будет|по акции)|— Акция|Предусмотрено)/).map(clean).filter(Boolean);
  return texts(lines.map((line, index) => {
    if (/^(?:максимальн(?:ая|ый)\s+(?:сумма|размер)\s+к[еэ]шб[еэ]ка|минимальн(?:ая|ый)\s+(?:сумма|чек)|срок действия)$/i.test(line) && lines[index + 1]) {
      return `${line}: ${lines[index + 1]}`;
    }
    return line;
  }));
}

export function offerMetadata(raw, bank, older = []) {
  const detailed = offerConditions(raw);
  const previous = detailed ? null : older.find(value => offerConditions(value.raw));
  const full = detailed || (previous ? offerConditions(previous.raw) : '');
  const conditions = texts([full, raw.previewConditions, raw.paymentCondition, raw.subtitle, raw.warningText]).join('\n\n');
  const lines = statements(conditions);
  let validityLabel = clean(raw.expirationLabel ?? raw.expirationDate);
  const startDate = clean(raw.startDate);
  const endDate = clean(raw.endDate);
  if (startDate && endDate) validityLabel = `${startDate} — ${endDate}`;
  else if (endDate) validityLabel = `До ${endDate}`;
  const range = lines.find(line => /^Срок действия:/i.test(line) && /\d{1,2}\.\d{1,2}\.\d{4}\s*[-—]\s*\d{1,2}\.\d{1,2}\.\d{4}/.test(line));
  if (range && !startDate) validityLabel = range.replace(/^Срок действия:\s*/i, '');
  if (!validityLabel) {
    validityLabel = lines.find(line => /^Срок действия:/i.test(line))?.replace(/^Срок действия:\s*/i, '')
      ?? lines.find(line => /^(?:до|с)\s+\d{1,2}[.\s]/i.test(line)) ?? '';
  }
  // Keep the original units and per-purchase/month qualifications.
  const limits = texts(lines.filter(line => /(?:\d|не огранич|без огранич)/i.test(line) && /максим(?:ум|альн)|лимит|не более|не превыш|ограничен.*(?:сумм|бонус|балл)/i.test(line)));
  if (!limits.length && raw.maxCashbackAmount != null) {
    limits.push(`Максимальный кешбэк: ${raw.maxCashbackAmount} (единица начисления в выгрузке не указана)`);
  }
  const priority = line => /нов.*(?:клиент|пользоват|покупател)|впервые|перв.*(?:покуп|заказ|оплат)|ранее не/i.test(line) ? 2 : /не (?:участв|начисля|суммир)|только|от\s+\d|одну покуп|подписк|промокод|акция (?:не )?действует|уровень/i.test(line) ? 1 : 0;
  const requirements = texts(lines.filter(line => /нов(?:ый|ым|ых|ого)\s+(?:клиент|пользоват|покупател)|впервые|перв(?:ую|ой|ый|ого)\s+(?:покуп|заказ|оплат)|ранее не|одну покуп|подписк|промокод|не (?:участв|начисля|суммир)|исключ|от\s+\d[\d\s]*\s*(?:₽|руб)|минимальн|оплат.*карт|только|необходим|акция (?:не )?действует|уровень|требуется/i.test(line)))
    .filter(line => !limits.includes(line))
    .sort((a, b) => priority(b) - priority(a));
  if (raw.minPurchaseAmount != null && !requirements.some(line => /минимальн|от\s+\d/i.test(line))) {
    requirements.push(`Минимальная покупка: ${raw.minPurchaseAmount} (единица в выгрузке не указана)`);
  }
  const links = [...(raw.links ?? []), ...(raw.details?.links ?? [])];
  if (raw.details?.rulesUrl) links.push({ text: 'Правила акции', url: raw.details.rulesUrl });
  if (previous) {
    links.push(...(previous.raw.links ?? []), ...(previous.raw.details?.links ?? []));
    if (previous.raw.details?.rulesUrl) links.push({ text: 'Правила акции', url: previous.raw.details.rulesUrl });
  }
  return {
    validityLabel: validityLabel || null,
    startDate: startDate || null, endDate: endDate || null,
    limits, requirements, conditions,
    conditionsCollectedAt: previous?.bank.collectedAt ?? raw.detailCollectedAt ?? bank.collectedAt ?? null,
    conditionsFromHistory: Boolean(previous),
    links: [...new Map(links.filter(link => link.url).map(link => [link.url, link])).values()],
  };
}
