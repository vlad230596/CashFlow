import { createServer } from 'node:http';
import { CashflowFixture } from '../browser/support/cashflow-adapter.mjs';

const fixture = new CashflowFixture();
fixture.offerName = 'Offline groceries';
let mode = 'online';
let changedAt = Date.now();
let calls = [];
const pending = new Set();
const send = (res, body, status = 200) => {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
};
createServer(async (req, res) => {
  let body = '';
  for await (const chunk of req) body += chunk;
  const url = new URL(req.url, 'http://127.0.0.1:18742');
  if (url.pathname === '/__qa/status') {
    return send(res, { mode, changedAt, calls, pending: pending.size, unexpected: fixture.unexpected });
  }
  if (url.pathname === '/__qa/control' && req.method === 'POST') {
    const control = JSON.parse(body);
    if (!['online', 'offline', 'hanging'].includes(control.mode)) return send(res, { error: 'Invalid mode' }, 400);
    mode = control.mode;
    changedAt = Date.now();
    if (control.reset) { calls = []; fixture.unexpected = []; }
    if (control.percent != null) fixture.percent = control.percent;
    if (mode !== 'hanging') {
      for (const release of pending) release();
      pending.clear();
    }
    return send(res, { mode });
  }
  if (!url.pathname.startsWith('/api/')) return send(res, { error: 'Not found' }, 404);
  const call = { path: url.pathname, method: req.method, mode, completed: false, at: Date.now() };
  calls.push(call);
  if (mode === 'offline') { req.socket.destroy(); return; }
  if (mode === 'hanging') {
    await new Promise((resolve) => {
      pending.add(resolve);
      res.on('close', () => { pending.delete(resolve); resolve(); });
    });
  }
  if (res.destroyed) return;
  try {
    const response = await fixture.respond({
      url: () => url.href, method: () => req.method,
      headers: () => req.headers, postDataJSON: () => JSON.parse(body),
    });
    send(res, response.body, response.status);
    call.completed = true;
  } catch {
    fixture.unexpected.push(`${req.method} ${url.pathname}`);
    send(res, { error: 'Synthetic API contract mismatch' }, 500);
  }
}).listen(18742, '127.0.0.1', () => console.log('Android synthetic API ready on 127.0.0.1:18742'));
