// Separate process: the offline suite retains its viewer identity. No user data.
import { createServer } from 'node:http';
const identity = { id: 7, username: 'offline-reader', role: 'admin' };
const token = 'synthetic-offline-token';
const offer = { id: 51, name: 'Offline groceries', card_id: 31, cashback_percent: 5,
  start_date: '2020-01-01T00:00:00', end_date: '2099-12-31T23:59:59',
  is_selected: true, is_bank_confirmed: true, canonical_keys: [] };
const bodies = {
  '/api/auth/me': identity,
  '/api/banks': [{ id: 11, name: 'Тестовый банк' }],
  '/api/users': [{ id: 21, name: 'Тестовый участник' }],
  '/api/cards': [{ id: 31, bank_id: 11, user_id: 21, payment_system: 'МИР', card_type: 'Дебетовая', last_four_digits: '4242', is_active: true }],
  '/api/active_cashback': [offer], '/api/cashback': [offer],
  '/api/canonical-categories': [], '/api/subscriptions': [],
  '/api/partner-offers': { items: [], total: 0 }, '/api/mcc': [],
  '/api/mcc/offline-snapshot': { schema_version: 1, as_of: new Date().toISOString().slice(0, 10), generated_at: new Date().toISOString(), catalogue: [], lookups: {}, offer_rules: {} },
  '/api/mcc/5411': { code: '5411', title: 'QA groceries' },
  '/api/mcc/5411/bank-rules': { mcc: { code: '5411', title: 'QA groceries' }, banks: [] },
};
const unexpected = [];
const calls = [];
createServer(async (req, res) => {
  const url = new URL(req.url, 'http://127.0.0.1:18742');
  const send = (body, status = 200) => {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(body));
  };
  if (url.pathname === '/__qa/status') return send({ calls, unexpected });
  let body = '';
  for await (const chunk of req) body += chunk;
  const call = { method: req.method, path: url.pathname, completed: false };
  calls.push(call);
  try {
    if (req.method === 'POST' && url.pathname === '/api/auth/login') {
      const credentials = JSON.parse(body);
      if (credentials.username !== identity.username || credentials.password !== 'synthetic-test-password') return send({ error: 'Fixture credentials required' }, 401);
      send({ user: identity, access_token: token, expires_at: '2099-01-01T00:00:00Z' });
    } else if (req.method === 'GET' && Object.hasOwn(bodies, url.pathname) && req.headers.authorization === `Bearer ${token}`) {
      send(bodies[url.pathname]);
    } else {
      unexpected.push(`${req.method} ${url.pathname}`);
      send({ error: 'Unexpected test API request' }, 404);
    }
    call.completed = true;
  } catch {
    unexpected.push(`${req.method} ${url.pathname}`);
    send({ error: 'Synthetic API contract mismatch' }, 500);
  }
}).listen(18742, '127.0.0.1', () => console.log('Back QA synthetic API ready'));
