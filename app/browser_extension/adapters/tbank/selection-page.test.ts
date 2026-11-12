// @vitest-environment happy-dom
// @vitest-environment-options {"url": "https://www.tbank.ru/mybank/bonuses/high-cashback/offer/42/"}
import { beforeAll, describe, expect, it, vi } from 'vitest';
import type { ProbeSource } from '../probe-runner';
import type { CashbackCategory } from '../types';

/*
 * Regression: the T-Bank offer page is where monthly categories are chosen.
 * Every automatic probe used to call `location.assign('/mybank/bonuses/')`
 * there, reloading the tab and discarding the owner's half-made choice.
 */

const saved: CashbackCategory = {
  type: 'standard', name: 'Тестовые аптеки', percent: 5, percentLabel: '5%', subtitle: null,
  description: null, iconUrl: null, iconBackgroundColor: null, selected: true, confirmed: true,
  group: 'Повышенный кэшбэк', expiresInLabel: null,
};

const registered: ProbeSource[] = [];

vi.mock('../probe-runner', async (importOriginal) => ({
  ...await importOriginal<typeof import('../probe-runner')>(),
  registerProbeListener: (source: ProbeSource) => { registered.push(source); },
}));
vi.mock('./cashback', async (importOriginal) => ({
  ...await importOriginal<typeof import('./cashback')>(),
  fetchTbankCashbackFromPage: async () => ({ categories: [saved], maxSelectable: 4, totalOptions: 8 }),
}));

beforeAll(async () => {
  vi.stubGlobal('defineContentScript', (definition: { main(): void }) => definition);
  const script = (await import('../../entrypoints/tbank.content')).default as unknown as { main(): void };
  script.main();
  // A checkbox form as on the offer page: an unsaved choice in progress.
  document.body.innerHTML = '<label><input type="checkbox" checked><span>12% Тестовый шопинг</span></label>';
});

describe('T-Bank selection page', () => {
  const fast = { timeoutMs: 600, quietMs: 60, pollMs: 15, advanceEveryMs: 0, maxAdvances: 3 };

  it.each(['passive', 'thorough'] as const)('is read without navigation in a %s probe', async (mode) => {
    const { runProbe } = await import('../probe-runner');
    const source = registered[0]!;
    const before = window.location.href;
    const assign = vi.spyOn(window.location, 'assign').mockImplementation(() => undefined);

    const probe = await runProbe(source, mode, undefined, fast);

    expect(assign).not.toHaveBeenCalled();
    expect(window.location.href).toBe(before);
    expect(probe.capture?.selectionPage).toBe(true);
    // The saved choice from the bank's API, not the unsaved checkboxes.
    expect(probe.categories.map((category) => category.name)).toEqual(['Тестовые аптеки']);
    expect(probe.selection.maxSelectable).toBe(4);
  });
});
