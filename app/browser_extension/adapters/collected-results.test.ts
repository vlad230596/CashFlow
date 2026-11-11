import { describe, expect, it } from 'vitest';
import {
  applyOutcome,
  buildImportDocument,
  exportGaps,
  restoreViews,
  serializeImportDocument,
  serializeViews,
  type BankView,
} from './collected-results';
import type { BankProbeOutcome } from './probe-client';
import type { BankId, CashbackCategory, PageProbe } from './types';

const category = (name: string, percent: number, selected = false, extra: Partial<CashbackCategory> = {}): CashbackCategory => ({
  type: 'standard', name, percent, percentLabel: `${percent}%`, subtitle: null, description: null,
  iconUrl: `https://cdn.example.test/${percent}.png`, iconBackgroundColor: null, selected, group: null,
  expiresInLabel: null, ...extra,
});

const probe = (bankId: BankId, categories: CashbackCategory[], stable = true): PageProbe => ({
  bankId, title: 'Кешбэк', url: `https://bank.example.test/${bankId}/cashback`, readyState: 'complete',
  authenticationStatus: 'authenticated', categories,
  selection: {
    isLocked: null, selectedCount: categories.filter((item) => item.selected).length,
    visibleCount: categories.length, maxSelectable: 3, totalOptions: categories.length, groups: [],
  },
  capture: { mode: 'thorough', stable, waitedMs: 900, reads: 6, advances: 0 },
});

const ready = (value: PageProbe): BankProbeOutcome => ({ status: 'ready', probe: value, message: null });
const missing = (status: 'auth' | 'waiting' | 'error', message: string): BankProbeOutcome => ({ status, probe: null, message });

const full = [
  category('Тестовые кафе', 5, true), category('Тестовые аптеки', 3, true), category('Тестовое такси', 7),
  category('Тестовые книги', 4, true), category('Тестовый спорт', 2), category('Тестовые цветы', 6),
];
const at = (time: string) => new Date(`2026-11-11T${time}:00+03:00`);

describe('accumulating probe results', () => {
  it('does not drop categories when a later probe saw only part of the list', () => {
    let view = applyOutcome(undefined, ready(probe('sber', full)), 'СберБанк', at('10:00'));
    // A later automatic probe ran while the list re-rendered; one category also changed selection.
    view = applyOutcome(view, ready(probe('sber', [category('Тестовые кафе', 5, false), category('Тестовые аптеки', 3, true)], false)), 'СберБанк', at('10:01'));

    expect(view.status).toBe('ready');
    expect(view.result?.categories).toHaveLength(6);
    expect(view.retainedCount).toBe(4);
    expect(view.result?.categories.find((item) => item.name === 'Тестовые кафе')?.selected).toBe(false);
    expect(view.result?.selection).toMatchObject({ selectedCount: 2, visibleCount: 6, maxSelectable: 3 });
  });

  it.each([
    missing('waiting', 'Ожидаю страницу категорий'),
    missing('auth', 'Требуется авторизация'),
    missing('error', 'Страница банка не ответила'),
  ])('keeps the last result when the next probe finds nothing ($status)', (outcome) => {
    const before = applyOutcome(undefined, ready(probe('ozon', full)), 'Ozon Банк', at('10:00'));
    const after = applyOutcome(before, outcome, 'Ozon Банк', at('10:05'));
    expect(after.status).toBe('ready');
    expect(after.liveStatus).toBe(outcome.status);
    expect(after.result).toBe(before.result);
    expect(after.message).toContain(outcome.message);
  });

  it('starts over in a new month', () => {
    const october = applyOutcome(undefined, ready(probe('vtb', full)), 'ВТБ', new Date('2026-10-31T20:00:00Z'));
    const november = applyOutcome(october, ready(probe('vtb', [category('Тестовые кафе', 5, true)])), 'ВТБ', new Date('2026-10-31T21:30:00Z'));
    expect(november.result?.categories).toHaveLength(1);
  });
});

describe('hand-off to the CashFlow app', () => {
  const bankName = (id: BankId) => ({ sber: 'СберБанк', alfa: 'Альфа-Банк' } as Record<string, string>)[id] ?? id;

  it('exports categories collected before a failed or partial probe', () => {
    const banks: BankId[] = ['sber', 'alfa'];
    let views: Partial<Record<BankId, BankView>> = {};
    const step = (id: BankId, outcome: BankProbeOutcome, time: string) => {
      views = { ...views, [id]: applyOutcome(views[id], outcome, bankName(id), at(time)) };
    };
    step('sber', ready(probe('sber', full)), '10:00');
    step('alfa', ready(probe('alfa', full.slice(0, 3))), '10:00');
    // The extended-offer collector moved the tabs to partner pages, then the
    // automatic probes ran again.
    step('sber', missing('waiting', 'Ожидаю страницу категорий'), '10:02');
    step('alfa', ready(probe('alfa', full.slice(0, 1), false)), '10:02');
    step('alfa', missing('auth', 'Требуется авторизация'), '10:03');

    const json = serializeImportDocument(buildImportDocument(banks, views, bankName, {}, at('10:04')), at('10:04'));
    const parsed = JSON.parse(json);

    expect(parsed.schemaVersion).toBe(1);
    expect(parsed.banks.map((bank: { bankId: string }) => bank.bankId)).toEqual(banks);
    for (const bank of parsed.banks) {
      // The backend skips banks that are not authenticated or lack categories.
      expect(bank.authenticationStatus).toBe('authenticated');
      expect(bank.categories.every((item: CashbackCategory) => item.name && typeof item.percent === 'number')).toBe(true);
      expect(bank.categories.some((item: Record<string, unknown>) => 'iconUrl' in item)).toBe(false);
    }
    expect(parsed.banks[0].categories).toHaveLength(6);
    expect(parsed.banks[1].categories).toHaveLength(3);
    expect(exportGaps(buildImportDocument(banks, views, bankName).banks)).toEqual([]);
  });

  it('survives closing and reopening the side panel', () => {
    const views = { sber: applyOutcome(undefined, ready(probe('sber', full)), 'СберБанк', at('10:00')) };
    const stored = JSON.parse(JSON.stringify(serializeViews(views, at('10:00'))));

    const restored = restoreViews(stored, ['sber', 'alfa'], at('12:00'));

    expect(restored.sber?.result?.categories).toEqual(views.sber.result?.categories);
    expect(restored.alfa).toBeUndefined();
    const document = buildImportDocument(['sber', 'alfa'], restored, bankName);
    expect(exportGaps(document.banks)).toEqual(['Альфа-Банк']);
  });

  it('does not restore a collection from another month or older than a day', () => {
    const views = { sber: applyOutcome(undefined, ready(probe('sber', full)), 'СберБанк', new Date('2026-10-31T12:00:00Z')) };
    const stored = serializeViews(views, new Date('2026-10-31T12:00:00Z'));
    expect(restoreViews(stored, ['sber'], new Date('2026-11-01T09:00:00Z'))).toEqual({});
    expect(restoreViews(stored, ['sber'], new Date('2026-10-31T12:00:00Z')).sber).toBeDefined();
    expect(restoreViews({ schemaVersion: 2 }, ['sber'], new Date())).toEqual({});
    const early = serializeViews({ sber: applyOutcome(undefined, ready(probe('sber', full)), 'СберБанк', at('09:00')) }, at('09:00'));
    expect(restoreViews(early, ['sber'], new Date('2026-11-12T09:30:00+03:00'))).toEqual({});
  });
});
