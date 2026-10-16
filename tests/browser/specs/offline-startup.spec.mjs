import { test, expect } from '@playwright/test';
import { NetworkController } from '../support/network-controller.mjs';
import { attachMeasurements } from '../support/evidence.mjs';
import {
  API_ORIGIN, OFFER_NAME, CashflowFixture, installFlutterAccessibility,
  searchBox, searchFor, cardResult, staleBanner, loginAndWarm, retryRefresh,
} from '../support/cashflow-adapter.mjs';

const startupBudgetMs = Number(process.env.OFFLINE_STARTUP_BUDGET_MS ?? 2000);
if (!Number.isFinite(startupBudgetMs) || startupBudgetMs <= 0) throw new Error('Invalid OFFLINE_STARTUP_BUDGET_MS');

for (const mode of ['offline', 'hanging']) {
  test(`cached data and search survive a new page with ${mode} API`, async ({ context, page }, testInfo) => {
    const fixture = new CashflowFixture();
    const network = new NetworkController(context, API_ORIGIN, (request) => fixture.respond(request));
    await network.install();
    await installFlutterAccessibility(context);
    const measurements = { mode, startupBudgetMs };
    try {
      await loginAndWarm(page, network);
      await page.close();
      network.setMode(mode);
      // A new document destroys the old Dart heap. Real browser storage remains.
      const reopened = await context.newPage();
      const started = performance.now();
      const deadline = () => Math.max(1, startupBudgetMs - (performance.now() - started));
      await reopened.goto('/', { waitUntil: 'commit', timeout: deadline() });
      await expect(searchBox(reopened)).toBeEnabled({ timeout: deadline() });
      measurements.usefulScreenMs = performance.now() - started;
      await searchFor(reopened, OFFER_NAME, deadline());
      await expect(searchBox(reopened)).toHaveValue(OFFER_NAME, { timeout: deadline() });
      await expect(cardResult(reopened)).toBeVisible({ timeout: deadline() });
      measurements.searchResultMs = performance.now() - started;
      expect(measurements.searchResultMs).toBeLessThanOrEqual(startupBudgetMs);
      await expect(reopened.getByLabel('Логин', { exact: true })).toHaveCount(0);
      await expect.poll(() => network.calls.some((call) => call.path === '/api/auth/me')).toBe(true);
      if (mode === 'hanging') {
        expect(network.pending.size).toBeGreaterThan(0);
        expect(network.calls.every((call) => !call.completed)).toBe(true);
        // Keep responses blocked for the full failure window, even after data
        // appears. This detects late clearing, redirects and timeout overlays.
        await reopened.waitForTimeout(Math.max(0, 30_000 - (performance.now() - started)));
        await expect(cardResult(reopened)).toBeVisible();
        await expect(searchBox(reopened)).toHaveValue(OFFER_NAME);
      } else {
        await expect(staleBanner(reopened)).toBeVisible();
      }

      fixture.percent = 9;
      const restoring = performance.now();
      network.restore();
      // A failed request needs the app's existing Retry action. Hanging requests
      // resume by receiving their delayed responses, without another navigation.
      if (mode === 'offline') await retryRefresh(reopened);
      await expect(cardResult(reopened, 9)).toBeVisible();
      measurements.refreshMs = performance.now() - restoring;
      await expect(cardResult(reopened, 5)).toHaveCount(0);
      await expect(searchBox(reopened)).toHaveValue(OFFER_NAME);
      await expect(staleBanner(reopened)).toHaveCount(0);
      await expect(reopened.getByLabel('Логин', { exact: true })).toHaveCount(0);
      expect(fixture.unexpected).toEqual([]);
      expect(network.unexpectedApiRequests).toEqual([]);
      expect(network.pageErrors).toEqual([]);
      await reopened.screenshot({ path: testInfo.outputPath('restored.png') });
    } finally {
      measurements.requests = network.calls;
      measurements.blockedExternalOrigins = [...new Set(network.externalRequests)];
      await attachMeasurements(testInfo, 'offline-measurements', measurements);
      await network.dispose();
    }
  });
}
