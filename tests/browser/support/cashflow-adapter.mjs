import { expect } from '@playwright/test';

export const API_ORIGIN = 'http://127.0.0.1:18741';
export const OFFER_NAME = 'Офлайн покупки';
export const identity = { id: 7, username: 'offline-reader', role: 'viewer' };

export class CashflowFixture {
  percent = 5;
  offerName = OFFER_NAME;
  unexpected = [];

  async respond(request) {
    const path = new URL(request.url()).pathname;
    if (path === '/api/auth/login' && request.method() === 'POST') {
      const credentials = request.postDataJSON();
      expect(credentials).toEqual({ username: identity.username, password: 'synthetic-test-password' });
      return { body: { user: identity, access_token: 'synthetic-offline-token', expires_at: '2099-01-01T00:00:00Z' } };
    }
    expect(request.headers().authorization).toBe('Bearer synthetic-offline-token');
    const offer = {
      id: 51, name: this.offerName, card_id: 31, cashback_percent: this.percent,
      start_date: '2020-01-01T00:00:00', end_date: '2099-12-31T23:59:59',
      is_selected: true, is_bank_confirmed: true, canonical_keys: [],
    };
    const bodies = {
      '/api/auth/me': identity,
      '/api/banks': [{ id: 11, name: 'Тестовый банк' }],
      '/api/users': [{ id: 21, name: 'Тестовый участник' }],
      '/api/cards': [{ id: 31, bank_id: 11, user_id: 21, payment_system: 'МИР', card_type: 'Дебетовая', last_four_digits: '4242', is_active: true }],
      '/api/active_cashback': [offer],
      '/api/cashback': [offer],
      '/api/canonical-categories': [],
      '/api/subscriptions': [],
      '/api/partner-offers': { items: [], total: 0 },
      '/api/mcc': [],
      '/api/mcc/offline-snapshot': { schema_version: 1, as_of: new Date().toISOString().slice(0, 10), generated_at: new Date().toISOString(), catalogue: [], lookups: {}, offer_rules: {} },
    };
    if (request.method() === 'GET' && Object.hasOwn(bodies, path)) return { body: bodies[path] };
    this.unexpected.push(`${request.method()} ${path}`);
    return { status: 501, body: { error: 'Unexpected test API request' } };
  }
}

// Flutter's accessible DOM is opt-in. Enable it when the engine inserts its
// standard accessibility placeholder; no private application state is accessed.
export async function installFlutterAccessibility(context) {
  await context.addInitScript(() => {
    const observer = new MutationObserver(() => {
      const placeholder = document.querySelector('flt-semantics-placeholder');
      if (placeholder) {
        placeholder.click();
        observer.disconnect();
      }
    });
    observer.observe(document, { childList: true, subtree: true });
  });
}

export const searchBox = (page) => page.getByRole('textbox', { name: /Что хотите купить/ });
export const staleBanner = (page) => page.getByRole('group', { name: /^Данные могли устареть Показана сохранённая копия/ });
export async function searchFor(page, text, timeout = 5000) {
  // Flutter replaces its accessibility input with an editing input on focus.
  // Real keyboard events reach the editor; fill() can update only the old DOM
  // mirror, leaving the Dart controller empty when the next rebuild happens.
  await searchBox(page).pressSequentially(text, { delay: 10, timeout });
}
export const cardResult = (page, percent = 5) => page.getByRole('group', {
  name: `${OFFER_NAME} •4242 ${percent}%`, exact: true,
}).filter({ has: page.getByRole('img', { name: 'Иконка банка Тестовый банк', exact: true }) })
  .filter({ has: page.getByRole('img', { name: 'Иконка пользователя Тестовый участник', exact: true }) });

export async function loginAndWarm(page, network) {
  await page.goto('/');
  await page.getByLabel('Логин', { exact: true }).fill(identity.username);
  await page.getByLabel('Пароль', { exact: true }).fill('synthetic-test-password');
  await page.getByRole('button', { name: 'Войти', exact: true }).click();
  await expect(searchBox(page)).toBeEnabled();
  await searchFor(page, OFFER_NAME);
  await expect(searchBox(page)).toHaveValue(OFFER_NAME);
  await expect(cardResult(page)).toBeVisible();
  // End of the sequential refresh comes after the persisted primary cache.
  await expect.poll(() => network.calls.some((call) => call.path === '/api/partner-offers' && call.completed)).toBe(true);
}

export async function retryRefresh(page) {
  await page.getByRole('button', { name: 'Повторить', exact: true }).click();
}
