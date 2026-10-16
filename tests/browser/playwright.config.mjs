import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './specs',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 60_000,
  expect: { timeout: 5_000 },
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: 'http://127.0.0.1:18741',
    viewport: { width: 1280, height: 900 },
    timezoneId: 'Europe/Moscow',
    locale: 'ru-RU',
    serviceWorkers: 'block',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  webServer: {
    command: 'node support/static-server.mjs',
    url: 'http://127.0.0.1:18741',
    reuseExistingServer: false,
    timeout: 10_000,
  },
});
