import { parseSelectionPlan, selectionPlanPeriodLabel } from '../../adapters/selection-plan';
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { strToU8, zipSync } from 'fflate';
import type { BankId, CashbackCategory, CashbackImportBankResult, CashbackImportDocument, CashbackSelectionPlanCategory, CashbackSelectionPlanDocument, ProbeMode } from '../../adapters/types';
import { isAuthenticationTab, probeBank, type BankProbeOutcome } from '../../adapters/probe-client';
import { applyOutcome, buildImportDocument, COLLECTED_STORAGE_KEY, emptyBankView, exportGaps, restoreViews, serializeImportDocument, serializeViews, type BankView } from '../../adapters/collected-results';
import { DEFAULT_BANK_IDS, findBank } from '../../banks/registry';
import { collectExtendedBank } from '../../adapters/extended/collect';
import { extendedFreshness, type ExtendedFreshness } from '../../adapters/extended/freshness';
import type { ExtendedBankResult } from '../../adapters/extended/types';
import './style.css';

type ImportRequest = { banks?: BankId[]; autoCollect?: boolean };
type ExportedIcon = {
  id: string;
  bankId: BankId;
  category: string;
  fileName: string;
  url: string;
};

function normalizedCategoryName(value: string): string {
  return value.toLocaleLowerCase('ru-RU')
    .replaceAll('ё', 'е')
    .replace(/[^a-zа-я0-9]+/giu, ' ')
    .trim();
}

function categoryMatches(
  category: CashbackCategory,
  desired: CashbackSelectionPlanCategory,
): boolean {
  if (normalizedCategoryName(category.name) !== normalizedCategoryName(desired.name)) return false;
  return desired.percent == null || category.percent == null ||
    Math.abs(category.percent - desired.percent) < 0.01;
}

const extendedRunLabels = {
  running: 'идёт сбор',
  interrupted: 'сбор прерван, данные неполные',
  partial: 'собрано с ошибками, данные неполные',
  complete: 'полный сбор',
  unknown: 'полнота неизвестна',
} as const;

function ExtendedStatus({ freshness, thisSession }: { freshness: ExtendedFreshness; thisSession: boolean }) {
  if (freshness.state === 'missing') {
    return <p className="extended-status extended-missing">Акции: ещё не собирались</p>;
  }
  const date = freshness.collectedAt.toLocaleString('ru-RU');
  const failure = freshness.state === 'fresh' || freshness.state === 'stale' ? freshness.lastFailure : null;
  const failureNote = failure && <><br />Повторный сбор {new Date(failure.at).toLocaleString('ru-RU')} не удался, показан предыдущий: {failure.error.replace(/^https?:\/\/\S+: /, '')}</>;
  if (freshness.state === 'failed') {
    return <p className="extended-status extended-stale">
      Акции: сбор {date} ({freshness.age}) не удался — в JSON не попадут.
      {freshness.error && <><br />{freshness.error.replace(/^https?:\/\/\S+: /, '')}</>}
    </p>;
  }
  if (freshness.state === 'stale') {
    return <p className="extended-status extended-stale">
      Акции: последний сбор {date} ({freshness.age}) — устарели, не показываются и не попадут в JSON
      {failureNote}
    </p>;
  }
  const good = freshness.run === 'complete';
  return <p className={`extended-status ${good ? 'extended-fresh' : 'extended-partial'}`}>
    {good ? '✓' : '!'} Акции обновлены {freshness.age} ({date}) · {extendedRunLabels[freshness.run]}
    {thisSession && ' · в этом сеансе'}
    {failureNote}
  </p>;
}

function CategoryIcon({ name, url, backgroundColor }: {
  name: string;
  url: string | null;
  backgroundColor: string | null;
}) {
  const [failed, setFailed] = useState(false);
  useEffect(() => setFailed(false), [url]);

  if (url && !failed) {
    return <img
      src={url}
      alt=""
      referrerPolicy="no-referrer"
      style={backgroundColor ? { backgroundColor } : undefined}
      onError={() => setFailed(true)}
    />;
  }

  return <span
    className="category-icon-fallback"
    aria-hidden="true"
    style={backgroundColor ? { backgroundColor } : undefined}
  >◆</span>;
}

function iconExtension(url: string): string {
  const dataMime = url.match(/^data:image\/([a-z0-9.+-]+)[;,]/i)?.[1]?.toLowerCase();
  if (dataMime === 'svg+xml') return 'svg';
  if (dataMime === 'jpeg') return 'jpg';
  if (dataMime) return dataMime.replace(/[^a-z0-9]/g, '') || 'img';
  try {
    const extension = new URL(url).pathname.match(/\.([a-z0-9]{2,5})$/i)?.[1];
    return extension?.toLowerCase() ?? 'img';
  } catch {
    return 'img';
  }
}

async function requestedBankIds(): Promise<BankId[]> {
  const stored = await browser.storage.local.get('cashflowImportRequest');
  const request = stored.cashflowImportRequest as ImportRequest | undefined;
  const valid = request?.banks?.filter((id) => DEFAULT_BANK_IDS.includes(id));
  return valid?.length ? valid : DEFAULT_BANK_IDS;
}

function App() {
  const [bankIds, setBankIds] = useState<BankId[]>(DEFAULT_BANK_IDS);
  const [initialized, setInitialized] = useState(false);
  const [views, setViews] = useState<Partial<Record<BankId, BankView>>>({});
  const [autoCollect, setAutoCollect] = useState(true);
  const [busy, setBusy] = useState(false);
  const [collectMessage, setCollectMessage] = useState<string | null>(null);
  const [iconsBusy, setIconsBusy] = useState(false);
  const [exportMessage, setExportMessage] = useState<string | null>(null);
  const [selectionPlan, setSelectionPlan] = useState<CashbackSelectionPlanDocument | null>(null);
  const [extended, setExtended] = useState<Partial<Record<BankId, ExtendedBankResult>>>({});
  const [extendedBusy, setExtendedBusy] = useState(false);
  const [extendedProgress, setExtendedProgress] = useState<string | null>(null);
  const [extendedCollectingBank, setExtendedCollectingBank] = useState<BankId | null>(null);
  const [extendedUpdatedNow, setExtendedUpdatedNow] = useState<ReadonlySet<BankId>>(new Set());
  const [now, setNow] = useState(() => new Date());
  const bankIdsRef = useRef(bankIds);
  const collectRunRef = useRef<Promise<void> | null>(null);
  const manualPendingRef = useRef(false);
  const extendedCollectingRef = useRef(false);

  useEffect(() => {
    bankIdsRef.current = bankIds;
  }, [bankIds]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  const probeAll = useCallback(async (mode: ProbeMode) => {
    await Promise.all(bankIdsRef.current.map(async (id) => {
      let outcome: BankProbeOutcome;
      try {
        outcome = await probeBank(id, mode);
      } catch (error) {
        outcome = { status: 'error', probe: null, message: String(error) };
      }
      // Each bank is merged as soon as it answers; a slow bank no longer
      // delays (or, on failure, discards) the others.
      setViews((current) => ({ ...current, [id]: applyOutcome(current[id], outcome, findBank(id).name, new Date()) }));
    }));
  }, []);

  /**
   * Manual clicks are never dropped: a click during an automatic or another
   * manual collection schedules one more thorough pass after it.
   */
  const collect = useCallback((manual: boolean): Promise<void> => {
    if (manual) {
      manualPendingRef.current = true;
      setBusy(true);
      setCollectMessage(null);
    }
    if (extendedCollectingRef.current) {
      if (manual) setCollectMessage('Идёт сбор расширенных предложений — категории соберутся сразу после него');
      return Promise.resolve();
    }
    if (collectRunRef.current) return collectRunRef.current;
    const run = (async () => {
      try {
        let mode: ProbeMode = manualPendingRef.current ? 'thorough' : 'passive';
        manualPendingRef.current = false;
        for (;;) {
          await probeAll(mode);
          if (!manualPendingRef.current || extendedCollectingRef.current) break;
          manualPendingRef.current = false;
          mode = 'thorough';
        }
      } finally {
        collectRunRef.current = null;
        if (!manualPendingRef.current) setBusy(false);
      }
    })();
    collectRunRef.current = run;
    return run;
  }, [probeAll]);

  useEffect(() => {
    void (async () => {
      const ids = await requestedBankIds();
      const stored = await browser.storage.local.get(['cashflowImportRequest', 'cashflowSelectionPlan', COLLECTED_STORAGE_KEY]);
      const request = stored.cashflowImportRequest as ImportRequest | undefined;
      // Results survive closing and reopening the side panel.
      setViews(restoreViews(stored[COLLECTED_STORAGE_KEY], ids, new Date()));
      setBankIds(ids);
      bankIdsRef.current = ids;
      setAutoCollect(request?.autoCollect ?? true);
      const plan = stored.cashflowSelectionPlan as CashbackSelectionPlanDocument | undefined;
      setSelectionPlan(parseSelectionPlan(plan));
      setInitialized(true);
    })();
  }, []);

  useEffect(() => {
    if (!initialized) return;
    const stored = serializeViews(views, new Date());
    if (!Object.keys(stored.banks).length) return;
    void browser.storage.local.set({ [COLLECTED_STORAGE_KEY]: stored }).catch(() => undefined);
  }, [initialized, views]);

  useEffect(() => {
    const listener = (changes: Record<string, Browser.storage.StorageChange>) => {
      if (!changes.cashflowSelectionPlan) return;
      const plan = changes.cashflowSelectionPlan.newValue as CashbackSelectionPlanDocument | undefined;
      setSelectionPlan(parseSelectionPlan(plan));
    };
    browser.storage.onChanged.addListener(listener);
    return () => browser.storage.onChanged.removeListener(listener);
  }, []);

  useEffect(() => {
    if (!initialized) return;
    void collect(false);
    // Bank list is the intentional trigger.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialized, bankIds.join(',')]);

  useEffect(() => {
    if (!autoCollect || !initialized) return undefined;
    const timer = window.setInterval(() => void collect(false), 5000);
    return () => window.clearInterval(timer);
  }, [autoCollect, initialized, collect]);

  async function clearCollected() {
    if (collectRunRef.current) await collectRunRef.current;
    setViews({});
    await browser.storage.local.remove(COLLECTED_STORAGE_KEY).catch(() => undefined);
    await collect(true);
  }

  async function openTabs() {
    for (const id of bankIds) {
      const bank = findBank(id);
      const existing = await browser.tabs.query({ url: bank.tabPatterns });
      if (!existing.length) {
        await browser.tabs.create({ url: bank.startUrl, active: false });
      }
    }
  }

  async function openBank(id: BankId) {
    const bank = findBank(id);
    const existing = await browser.tabs.query({ url: bank.tabPatterns });
    const authTab = views[id]?.liveStatus === 'auth' || views[id]?.status === 'auth'
      ? existing.find(isAuthenticationTab)
      : undefined;
    const tab = authTab ?? existing.find((candidate) =>
      bank.preferredUrlParts.some((part) => candidate.url?.includes(part)),
    ) ?? existing[0];
    if (tab?.id != null) {
      await browser.tabs.update(tab.id, { active: true });
      if (tab.windowId != null) await browser.windows.update(tab.windowId, { focused: true });
      return;
    }
    await browser.tabs.create({ url: bank.startUrl, active: true });
  }

  useEffect(() => {
    void (async () => {
      const keys = DEFAULT_BANK_IDS.map((id) => `cashflowExtendedHistory:${id}`);
      const stored = await browser.storage.local.get(keys);
      setExtended(Object.fromEntries(DEFAULT_BANK_IDS.flatMap((id) => {
        const value = stored[`cashflowExtendedHistory:${id}`] as ExtendedBankResult | undefined;
        return value?.bankId === id ? [[id, value]] : [];
      })));
    })();
  }, []);

  async function collectExtended() {
    // A ref, not state: two quick clicks happen before React re-renders.
    if (extendedCollectingRef.current) return;
    if (collectRunRef.current) await collectRunRef.current;
    extendedCollectingRef.current = true;
    setExtendedBusy(true);
    const failures: string[] = [];
    try {
      await openTabs();
      for (const id of bankIds) {
        setExtendedProgress(`${findBank(id).name}: читаю каталог`);
        setExtendedCollectingBank(id);
        try {
          const result = await collectExtendedBank(id, (partial) => {
            setExtended((current) => ({ ...current, [id]: partial }));
            setExtendedProgress(`${findBank(id).name}: ${partial.offers.length}/${partial.previewCount}`);
          });
          setExtended((current) => ({ ...current, [id]: result }));
          setExtendedUpdatedNow((current) => new Set(current).add(id));
        } catch (error) {
          failures.push(`${findBank(id).name}: ${String(error)}`);
          setExtendedProgress(failures.at(-1)!);
          const key = `cashflowExtendedHistory:${id}`;
          const stored = (await browser.storage.local.get(key))[key] as ExtendedBankResult | undefined;
          setExtended((current) => ({ ...current, [id]: stored?.bankId === id ? stored : undefined }));
        }
      }
      setExtendedProgress(failures.length ? `Сбор завершён с ошибками: ${failures.join('; ')}` : 'Сбор расширенных предложений завершён');
    } finally {
      extendedCollectingRef.current = false;
      setExtendedCollectingBank(null);
      setExtendedBusy(false);
      if (manualPendingRef.current) void collect(true);
    }
  }

  const freshness = useMemo(() => Object.fromEntries(bankIds.map((id) => [
    id,
    extendedFreshness(extended[id], now, extendedCollectingBank === id),
  ])) as Record<BankId, ExtendedFreshness>, [bankIds, extended, now, extendedCollectingBank]);
  const freshBankCount = bankIds.filter((id) => freshness[id].state === 'fresh').length;
  const completeBankCount = bankIds.filter((id) => {
    const value = freshness[id];
    return value.state === 'fresh' && value.run === 'complete';
  }).length;

  const output = useMemo<CashbackImportDocument>(() => buildImportDocument(
    bankIds,
    views,
    (id) => findBank(id).name,
    // Only collections from the last day are exported; older ones would
    // mark long-gone offers as available again.
    Object.fromEntries(bankIds.flatMap((id) => {
      const extra = extended[id];
      const fresh = freshness[id];
      return extra && fresh.state === 'fresh' ? [[id, {
        extendedOffers: fresh.offers,
        extendedSummary: {
          collectedAt: extra.collectedAt,
          previewCount: extra.previewCount,
          reusedCount: extra.reusedCount,
          openedCount: extra.openedCount,
          previewOnlyCount: extra.previewOnlyCount,
          errors: extra.errors,
          runStatus: extra.runStatus,
        },
      }]] : [];
    })),
  ), [bankIds, views, extended, freshness]);

  const readyCount = output.banks.filter((bank) => bank.collectionStatus === 'ready').length;

  const outputRef = useRef(output);
  outputRef.current = output;

  async function downloadJson() {
    setExportMessage(null);
    // Export what the running collection is about to deliver, not a snapshot
    // taken in the middle of it.
    if (collectRunRef.current) {
      setExportMessage('Дожидаюсь завершения сбора…');
      await collectRunRef.current;
      await new Promise((resolve) => window.setTimeout(resolve, 0));
    }
    const document = outputRef.current;
    const json = serializeImportDocument(document);
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    // A data: URL silently failed for large exports (Cyrillic text triples in
    // size when percent-encoded and Chrome caps URL length at 2 MB).
    const url = URL.createObjectURL(new Blob([json], { type: 'application/json' }));
    try {
      await browser.downloads.download({ url, filename: `CashFlow/cashback-${stamp}.json`, saveAs: true });
      const gaps = exportGaps(document.banks);
      const exportedCount = document.banks.length - gaps.length;
      setExportMessage(`JSON сохранён: категории ${exportedCount} из ${document.banks.length} банков` +
        (gaps.length ? `. Без категорий (будут пропущены при импорте): ${gaps.join(', ')}` : ''));
    } catch (error) {
      setExportMessage(`JSON не сохранён: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      // The download reads the blob asynchronously after the save dialog.
      window.setTimeout(() => URL.revokeObjectURL(url), 60_000);
    }
  }

  async function downloadIcons() {
    const icons = new Map<string, ExportedIcon>();
    for (const bank of output.banks) {
      for (const category of bank.categories) {
        if (!category.iconId || !category.iconUrl || icons.has(category.iconId)) continue;
        const fileName = `${category.iconId}.${iconExtension(category.iconUrl)}`;
        icons.set(category.iconId, {
          id: category.iconId,
          bankId: bank.bankId,
          category: category.name,
          fileName,
          url: category.iconUrl,
        });
      }
      for (const offer of bank.extendedOffers ?? []) {
        for (const [role, url] of [['icon', offer.iconUrl], ['artwork', offer.artworkUrl]] as const) {
          if (!url) continue;
          const id = `${bank.bankId}-offer-${offer.id}-${role}`;
          if (icons.has(id)) continue;
          icons.set(id, {
            id, bankId: bank.bankId, category: offer.name,
            fileName: `${id.replace(/[^a-z0-9_-]/gi, '_')}.${iconExtension(url)}`,
            url,
          });
        }
      }
    }
    if (!icons.size) {
      setExportMessage('Нет собранных значков');
      return;
    }

    setIconsBusy(true);
    setExportMessage(null);
    try {
      const zipFiles: Record<string, Uint8Array> = {};
      const exportedIcons: Omit<ExportedIcon, 'url'>[] = [];
      const failedIcons: Array<Pick<ExportedIcon, 'id' | 'bankId' | 'category'>> = [];
      for (const icon of icons.values()) {
        try {
          const response = await fetch(icon.url, { credentials: 'include' });
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          zipFiles[`icons/${icon.fileName}`] = new Uint8Array(await response.arrayBuffer());
          const { url: _url, ...manifestIcon } = icon;
          exportedIcons.push(manifestIcon);
        } catch {
          const { id, bankId, category } = icon;
          failedIcons.push({ id, bankId, category });
        }
      }
      const manifest = JSON.stringify({
        schemaVersion: 1,
        exportedAt: new Date().toISOString(),
        icons: exportedIcons,
        failedIcons,
      }, null, 2);
      zipFiles['manifest.json'] = strToU8(manifest);

      const archive = zipSync(zipFiles, { level: 6 });
      const archiveBuffer = archive.buffer.slice(
        archive.byteOffset,
        archive.byteOffset + archive.byteLength,
      ) as ArrayBuffer;
      const archiveUrl = URL.createObjectURL(new Blob([archiveBuffer], { type: 'application/zip' }));
      const stamp = new Date().toISOString().replace(/[:.]/g, '-');
      try {
        await browser.downloads.download({
          url: archiveUrl,
          filename: `CashFlow/cashflow-icons-${stamp}.zip`,
          saveAs: true,
        });
      } finally {
        window.setTimeout(() => URL.revokeObjectURL(archiveUrl), 60_000);
      }
      setExportMessage(failedIcons.length
        ? `Архив готов: ${exportedIcons.length} из ${icons.size} значков`
        : `Архив готов: ${exportedIcons.length} значков`);
    } finally {
      setIconsBusy(false);
    }
  }

  return <main>
    <header>
      <div><h1>CashFlow Importer</h1><p>{readyCount} из {bankIds.length} банков готовы</p></div>
      <label className="auto-toggle"><input type="checkbox" checked={autoCollect} onChange={(event) => setAutoCollect(event.target.checked)} />Автосбор</label>
    </header>
    <div className="actions">
      <button type="button" className="secondary" onClick={openTabs}>Открыть вкладки</button>
      <button type="button" onClick={() => void collect(true)} disabled={busy}>{busy ? 'Собираю…' : 'Собрать все'}</button>
      <button type="button" className="secondary" onClick={() => void clearCollected()} disabled={busy}>Собрать заново</button>
      <button type="button" className="extended-action" onClick={() => void collectExtended()} disabled={extendedBusy}>
        {extendedBusy ? 'Собираю расширенные…' : 'Собрать расширенные предложения'}
      </button>
      <button type="button" className="icons" onClick={() => void downloadIcons()} disabled={iconsBusy}>{iconsBusy ? 'Собираю ZIP…' : 'Скачать значки ZIP'}</button>
      <button type="button" className="success" onClick={downloadJson}>Скачать JSON</button>
    </div>
    {collectMessage && <p className="export-message">{collectMessage}</p>}
    {exportMessage && <p className="export-message">{exportMessage}</p>}
    {extendedProgress && <p className="export-message">{extendedProgress}</p>}
    <p className={`extended-overview ${completeBankCount === bankIds.length ? 'extended-fresh' : 'extended-partial'}`}>
      Акции за последние 24 ч: {freshBankCount} из {bankIds.length} банков, полностью — {completeBankCount}.
      {freshBankCount < bankIds.length && ' Остальные банки попадут в JSON без акций.'}
    </p>
    {selectionPlan && <section className="selection-plan">
      <div className="plan-heading"><div><h2>План на выбранный период</h2><p>{selectionPlanPeriodLabel(selectionPlan)}</p></div><span>Только подсказка</span></div>
      <p>После сохранения категорий в банке проверьте результат и экспортируйте новый JSON в CashFlow. До подтверждения категории не учитываются в активном кешбэке.</p>
      <button type="button" onClick={() => void collect(true)} disabled={busy}>Проверить подтверждение в банках</button>
      {selectionPlan.banks.map((planBank) => {
        const view = views[planBank.bankId];
        const ready = view?.status === 'ready';
        const actual = view?.result?.categories ?? [];
        const desired = planBank.desiredCategories;
        const bankDesired = selectionPlan.banks
          .filter((item) => item.bankId === planBank.bankId)
          .flatMap((item) => item.desiredCategories);
        const removals = ready ? actual.filter((category) => category.type === 'standard' && category.selected &&
          !bankDesired.some((item) => categoryMatches(category, item))) : [];
        return <div className="plan-bank" key={`${planBank.bankId}-${planBank.cardId}`}>
          <strong>{planBank.cardLabel}</strong>
          <ul>
            {desired.map((item, index) => {
              const match = actual.find((category) => categoryMatches(category, item));
              const confirmed = match?.selected && (match.confirmed === true || view?.result?.selection.isLocked === true);
              const state = !ready ? 'pending' : !match ? 'missing' : confirmed ? 'done' : match.selected ? 'pending' : 'select';
              return <li className={`plan-${state}`} key={`${item.name}-${index}`}>
                <span>{state === 'pending' ? '…' : state === 'done' ? '✓' : state === 'select' ? '+' : '!'}</span>
                <b>{item.percent != null ? `${item.percent}% ` : ''}{item.name}</b>
                <small>{state === 'pending' ? 'ожидает подтверждения банка' : state === 'done' ? 'подтверждено банком' : state === 'select' ? 'нужно выбрать' : 'не найдено на странице'}</small>
              </li>;
            })}
            {removals.map((category, index) => <li className="plan-remove" key={`remove-${category.name}-${index}`}>
              <span>−</span><b>{category.percentLabel} {category.name}</b><small>нужно снять</small>
            </li>)}
            {ready && !desired.length && !removals.length && <li className="plan-done"><span>✓</span><b>Ничего выбирать не нужно</b></li>}
            {!ready && !desired.length && <li className="plan-pending"><span>…</span><b>Ожидаем страницу банка</b></li>}
          </ul>
        </div>;
      })}
    </section>}
    <section className="banks">{bankIds.map((id) => {
      const bank = findBank(id);
      const view = views[id] ?? emptyBankView();
      const result = view.result;
      const fresh = freshness[id];
      const extra = fresh.state === 'fresh' ? extended[id] : undefined;
      return <article key={id} className={`bank bank-${view.status}`}>
        <div className="bank-heading"><div><h2>{bank.name}</h2><span className="status">
          {view.status === 'ready' && 'Готово'}{view.status === 'auth' && 'Нужен вход'}{view.status === 'collecting' && 'Сбор…'}{view.status === 'waiting' && 'Ожидание'}{view.status === 'error' && 'Ошибка'}
        </span></div><button type="button" className="link-button" onClick={() => void openBank(id)}>Открыть</button></div>
        {view.message && <p className="message">{view.message}</p>}
        {!!view.retainedCount && <p className="message">Ещё {view.retainedCount} из прошлых проверок сохранены — последняя проверка их не показала («Собрать заново» сбросит)</p>}
        <ExtendedStatus freshness={fresh} thisSession={extendedUpdatedNow.has(id)} />
        {extra && fresh.state === 'fresh' && <details><summary>Расширенные предложения ({fresh.offers.length})</summary>
          <p className="summary">В каталоге банка: {extra.previewCount} · Из истории: {extra.reusedCount} · Открыто: {extra.openedCount} · Только превью: {extra.previewOnlyCount}</p>
          {extra.errors.length > 0 && <p className="message">Ошибок: {extra.errors.length}</p>}
          <ul className="categories">{fresh.offers.map((offer) => <li key={offer.id}>
            <CategoryIcon name={offer.name} url={offer.iconUrl} backgroundColor={null} />
            <span><strong>{offer.rateLabel} {offer.name}</strong>
              {offer.offerKind !== 'cashback' && <small>{offer.offerKind === 'discount' ? 'Скидка' : 'Другое предложение'}</small>}
              {offer.group && <small>{offer.group}</small>}
              {offer.expirationLabel && <small>{offer.expirationLabel}</small>}
              {offer.previewConditions && <small>{offer.previewConditions}</small>}
              {offer.conditions && <small className="details-copy">{offer.conditions}</small>}
              {offer.detailsStatus !== 'complete' && <small>{offer.detailsError || 'Только превью'}</small>}
            </span>
          </li>)}</ul></details>}
        {result && <><p className="summary">Выбрано: {result.selection.selectedCount}{result.selection.maxSelectable != null && ` из ${result.selection.maxSelectable}`} · Найдено: {result.selection.visibleCount}{result.selection.totalOptions != null && ` / ${result.selection.totalOptions}`}</p>
          <details><summary>Все категории ({result.categories.length})</summary><ul className="categories">{result.categories.map((category, index) => <li className={category.selected ? 'category-selected' : 'category-unselected'} key={`${category.name}-${category.percentLabel}-${index}`}>
            <CategoryIcon name={category.name} url={category.iconUrl} backgroundColor={category.iconBackgroundColor} /><span><strong>{category.percentLabel} {category.name}</strong>
              <small className={`selection-label ${category.selected && (category.confirmed === true || result.selection.isLocked === true) ? 'selection-selected' : 'selection-unselected'}`}>{category.type === 'task_bonus' ? 'За задание' : category.selected && (category.confirmed === true || result.selection.isLocked === true) ? '✓ Подтверждено банком' : category.selected ? 'Ожидает подтверждения банка' : 'Не выбрано'}</small>
              {category.expiresInLabel && <small>{category.expiresInLabel}</small>}{category.group && <small>{category.group}</small>}
              {category.subtitle && category.subtitle !== category.expiresInLabel && <small>{category.subtitle}</small>}{category.description && <small className="details-copy">{category.description}</small>}
            </span></li>)}</ul></details></>}
      </article>;
    })}</section>
  </main>;
}

createRoot(document.getElementById('root')!).render(<App />);
