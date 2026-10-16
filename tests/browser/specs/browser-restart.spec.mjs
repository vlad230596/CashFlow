import { test, expect } from '@playwright/test';
import { NetworkController } from '../support/network-controller.mjs';
import { PersistentBrowser } from '../support/persistent-browser.mjs';
import { attachMeasurements } from '../support/evidence.mjs';
import {
  API_ORIGIN, OFFER_NAME, CashflowFixture, installFlutterAccessibility,
  searchBox, searchFor, cardResult, loginAndWarm,
} from '../support/cashflow-adapter.mjs';

test('cached identity and data survive a complete Chromium process restart', async ({}, testInfo) => {
  const browser = new PersistentBrowser();
  const fixture = new CashflowFixture();
  let network;
  let context;
  const measurements = {};
  const budget = Number(process.env.OFFLINE_STARTUP_BUDGET_MS ?? 2000);
  try {
    context = await browser.open();
    network = new NetworkController(context, API_ORIGIN, (request) => fixture.respond(request));
    await network.install();
    await installFlutterAccessibility(context);
    const page = await context.newPage();
    await loginAndWarm(page, network);
    expect(network.unexpectedApiRequests).toEqual([]);
    expect(network.pageErrors).toEqual([]);
    await network.dispose();
    await browser.close();

    context = await browser.open();
    network = new NetworkController(context, API_ORIGIN, (request) => fixture.respond(request));
    network.setMode('offline');
    await network.install();
    await installFlutterAccessibility(context);
    const reopened = await context.newPage();
    const started = performance.now();
    const remaining = () => Math.max(1, budget - (performance.now() - started));
    await reopened.goto(API_ORIGIN, { waitUntil: 'commit', timeout: remaining() });
    await expect(searchBox(reopened)).toBeEnabled({ timeout: remaining() });
    measurements.usefulScreenMs = performance.now() - started;
    await searchFor(reopened, OFFER_NAME, remaining());
    await expect(searchBox(reopened)).toHaveValue(OFFER_NAME, { timeout: remaining() });
    await expect(cardResult(reopened)).toBeVisible({ timeout: remaining() });
    measurements.searchResultMs = performance.now() - started;
    expect(measurements.searchResultMs).toBeLessThanOrEqual(budget);
    await expect(reopened.getByLabel('Логин', { exact: true })).toHaveCount(0);
    expect(fixture.unexpected).toEqual([]);
    expect(network.unexpectedApiRequests).toEqual([]);
    expect(network.pageErrors).toEqual([]);
    await reopened.screenshot({ path: testInfo.outputPath('browser-restart.png') });
  } finally {
    await attachMeasurements(testInfo, 'restart-measurements', measurements);
    await network?.dispose();
    await browser.dispose();
  }
});
