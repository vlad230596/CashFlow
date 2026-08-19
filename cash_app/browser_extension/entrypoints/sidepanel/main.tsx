import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import type { BankId, CashbackImportBankResult, CashbackImportDocument, CollectionStatus, PageProbe } from '../../adapters/types';
import { DEFAULT_BANK_IDS, findBank } from '../../banks/registry';
import './style.css';

type BankViewStatus = CollectionStatus;
type BankView = { status: BankViewStatus; result: CashbackImportBankResult | null; message: string | null };
type ImportRequest = { banks?: BankId[]; autoCollect?: boolean };

const emptyBankView = (): BankView => ({ status: 'waiting', result: null, message: null });
const isLoginUrl = (url: string) => /\/login|\/signin|\/auth\/|passport\.yandex|private\.auth\.alfabank|\/passport\/|\/apps\/auth|\/csafront\/index\.do(?:#\/?)?$/i.test(url);
const isAuthenticationTab = (tab: { url?: string; title?: string }) =>
  isLoginUrl(tab.url ?? '') || /^(?:вход|авторизация)/i.test(tab.title ?? '');

async function requestedBankIds(): Promise<BankId[]> {
  const stored = await browser.storage.local.get('cashflowImportRequest');
  const request = stored.cashflowImportRequest as ImportRequest | undefined;
  const valid = request?.banks?.filter((id) => DEFAULT_BANK_IDS.includes(id));
  return valid?.length ? valid : DEFAULT_BANK_IDS;
}

async function probeBank(bankId: BankId): Promise<BankView> {
  const bank = findBank(bankId);
  const tabs = await browser.tabs.query({ url: bank.tabPatterns });
  if (!tabs.length) return emptyBankView();

  const responses = await Promise.all(tabs.map(async (tab) => {
    if (tab.id == null) return null;
    try {
      return await browser.tabs.sendMessage(tab.id, { type: 'cashflow:probe-page' }) as PageProbe;
    } catch {
      return null;
    }
  }));
  const response = responses
    .filter((candidate): candidate is PageProbe => candidate != null)
    .sort((left, right) => {
      const countDifference = right.categories.length - left.categories.length;
      if (countDifference) return countDifference;
      const preferredDifference = Number(bank.preferredUrlParts.some((part) => right.url.includes(part))) -
        Number(bank.preferredUrlParts.some((part) => left.url.includes(part)));
      if (preferredDifference) return preferredDifference;
      return Number(right.authenticationStatus === 'authentication_required') -
        Number(left.authenticationStatus === 'authentication_required');
    })[0];

  if (!response) {
    return tabs.some(isAuthenticationTab)
      ? { status: 'auth', result: null, message: 'Требуется авторизация' }
      : { status: 'error', result: null, message: 'Обновите вкладку после загрузки расширения' };
  }
  if (
    response.authenticationStatus === 'authentication_required' ||
    (response.categories.length === 0 && tabs.some(isAuthenticationTab))
  ) {
    return { status: 'auth', result: null, message: 'Требуется авторизация' };
  }
  if (response.authenticationStatus === 'unknown' && response.categories.length === 0) {
    return { status: 'waiting', result: null, message: 'Ожидаю страницу категорий' };
  }
  return {
    status: 'ready',
    result: {
      ...response,
      bankName: bank.name,
      collectionStatus: 'ready',
      collectedAt: new Date().toISOString(),
      message: null,
    },
    message: null,
  };
}

function App() {
  const [bankIds, setBankIds] = useState<BankId[]>(DEFAULT_BANK_IDS);
  const [views, setViews] = useState<Record<string, BankView>>({});
  const [autoCollect, setAutoCollect] = useState(true);
  const [busy, setBusy] = useState(false);
  const viewsRef = useRef(views);
  const collectingRef = useRef(false);

  useEffect(() => {
    viewsRef.current = views;
  }, [views]);

  const collect = useCallback(async (onlyPending = false, showBusy = true) => {
    if (collectingRef.current) return;
    const ids = onlyPending
      ? bankIds.filter((id) => viewsRef.current[id]?.status !== 'ready')
      : bankIds;
    if (!ids.length) return;
    collectingRef.current = true;
    if (showBusy) setBusy(true);
    try {
      const entries = await Promise.all(ids.map(async (id) => [id, await probeBank(id)] as const));
      setViews((current) => ({ ...current, ...Object.fromEntries(entries) }));
    } finally {
      collectingRef.current = false;
      if (showBusy) setBusy(false);
    }
  }, [bankIds]);

  useEffect(() => {
    void (async () => {
      const ids = await requestedBankIds();
      const stored = await browser.storage.local.get('cashflowImportRequest');
      const request = stored.cashflowImportRequest as ImportRequest | undefined;
      setBankIds(ids);
      setAutoCollect(request?.autoCollect ?? true);
    })();
  }, []);

  useEffect(() => {
    void collect(false, false);
    // Bank list is the intentional trigger; collect identity changes while results arrive.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [bankIds.join(',')]);

  useEffect(() => {
    if (!autoCollect) return undefined;
    const timer = window.setInterval(() => void collect(true, false), 5000);
    return () => window.clearInterval(timer);
  }, [autoCollect, collect]);

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
    const authTab = views[id]?.status === 'auth'
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

  const output = useMemo<CashbackImportDocument>(() => ({
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    requestedBanks: bankIds,
    banks: bankIds.map((id): CashbackImportBankResult => {
      const bank = findBank(id);
      const view = views[id] ?? emptyBankView();
      if (view.result) return view.result;
      return {
        bankId: id,
        bankName: bank.name,
        collectionStatus: view.status,
        collectedAt: null,
        title: null,
        url: null,
        readyState: null,
        authenticationStatus: view.status === 'auth' ? 'authentication_required' : 'unknown',
        selection: {
          selectedCount: 0,
          visibleCount: 0,
          maxSelectable: null,
          totalOptions: null,
          groups: [],
        },
        categories: [],
        message: view.message,
      };
    }),
  }), [bankIds, views]);

  const readyCount = output.banks.filter((bank) => bank.collectionStatus === 'ready').length;

  async function downloadJson() {
    const json = JSON.stringify({ ...output, generatedAt: new Date().toISOString() }, null, 2);
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    await browser.downloads.download({
      url: `data:application/json;charset=utf-8,${encodeURIComponent(json)}`,
      filename: `CashFlow/cashback-${stamp}.json`,
      saveAs: true,
    });
  }

  return <main>
    <header>
      <div><h1>CashFlow Importer</h1><p>{readyCount} из {bankIds.length} банков готовы</p></div>
      <label className="auto-toggle"><input type="checkbox" checked={autoCollect} onChange={(event) => setAutoCollect(event.target.checked)} />Автосбор</label>
    </header>
    <div className="actions">
      <button type="button" className="secondary" onClick={openTabs}>Открыть вкладки</button>
      <button type="button" onClick={() => void collect(false)} disabled={busy}>{busy ? 'Собираю…' : 'Собрать все'}</button>
      <button type="button" className="success" onClick={downloadJson}>Скачать JSON</button>
    </div>
    <section className="banks">{bankIds.map((id) => {
      const bank = findBank(id);
      const view = views[id] ?? emptyBankView();
      const result = view.result;
      return <article key={id} className={`bank bank-${view.status}`}>
        <div className="bank-heading"><div><h2>{bank.name}</h2><span className="status">
          {view.status === 'ready' && 'Готово'}{view.status === 'auth' && 'Нужен вход'}{view.status === 'collecting' && 'Сбор…'}{view.status === 'waiting' && 'Ожидание'}{view.status === 'error' && 'Ошибка'}
        </span></div><button type="button" className="link-button" onClick={() => void openBank(id)}>Открыть</button></div>
        {view.message && <p className="message">{view.message}</p>}
        {result && <><p className="summary">Выбрано: {result.selection.selectedCount}{result.selection.maxSelectable != null && ` из ${result.selection.maxSelectable}`} · Найдено: {result.selection.visibleCount}{result.selection.totalOptions != null && ` / ${result.selection.totalOptions}`}</p>
          <details><summary>Все категории ({result.categories.length})</summary><ul className="categories">{result.categories.map((category, index) => <li className={category.selected ? 'category-selected' : 'category-unselected'} key={`${category.name}-${category.percentLabel}-${index}`}>
            {category.iconUrl && <img src={category.iconUrl} alt="" />}<span><strong>{category.percentLabel} {category.name}</strong>
              <small className={`selection-label ${category.selected ? 'selection-selected' : 'selection-unselected'}`}>{category.selected ? '✓ Выбрано' : 'Не выбрано'}</small>
              {category.expiresInLabel && <small>{category.expiresInLabel}</small>}{category.group && <small>{category.group}</small>}
              {category.subtitle && category.subtitle !== category.expiresInLabel && <small>{category.subtitle}</small>}{category.description && <small className="details-copy">{category.description}</small>}
            </span></li>)}</ul></details></>}
      </article>;
    })}</section>
  </main>;
}

createRoot(document.getElementById('root')!).render(<App />);
