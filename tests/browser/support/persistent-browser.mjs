import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { chromium } from '@playwright/test';

/** Reuses an actual Chromium profile across process exits, not storageState.
 * This preserves localStorage, IndexedDB and browser-managed encryption keys.
 */
export class PersistentBrowser {
  async open() {
    this.profile ??= await mkdtemp(join(tmpdir(), 'offline-browser-'));
    this.context = await chromium.launchPersistentContext(this.profile, {
      headless: true,
      viewport: { width: 1280, height: 900 },
      timezoneId: 'Europe/Moscow',
      locale: 'ru-RU',
      serviceWorkers: 'block',
    });
    return this.context;
  }

  async close() {
    await this.context?.close();
    this.context = null;
  }

  async dispose() {
    await this.close();
    // Only remove the exact task-owned temporary profile, under the temp root.
    if (this.profile && resolve(this.profile).startsWith(resolve(tmpdir()) + sep + 'offline-browser-')) {
      await rm(this.profile, { recursive: true, force: true });
    }
  }
}
