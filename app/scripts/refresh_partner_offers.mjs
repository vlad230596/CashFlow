import { mkdir, writeFile } from 'node:fs/promises';

// Uses the already open extension; Chrome must expose its debugging port.
const port = Number(process.argv.slice(2).find(arg => !arg.startsWith('--')) ?? 9223);
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find(t => t.type === 'page' && t.url.startsWith('chrome-extension://') && t.url.endsWith('/sidepanel.html'));
if (!target) throw new Error('Open the CashFlow extension side panel first.');
const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
let nextId = 0;
const pending = new Map();
socket.onmessage = ({ data }) => {
  const message = JSON.parse(data);
  const request = pending.get(message.id);
  if (!request) return;
  pending.delete(message.id);
  if (message.error || message.result?.exceptionDetails) request.reject(new Error(JSON.stringify(message.error ?? message.result.exceptionDetails)));
  else request.resolve(message.result.result.value);
};
function evaluate(expression) {
  return new Promise((resolve, reject) => {
    const id = ++nextId;
    pending.set(id, { resolve, reject });
    socket.send(JSON.stringify({ id, method: 'Runtime.evaluate', params: { expression, awaitPromise: true, returnByValue: true } }));
  });
}
try {
  if (process.argv.includes('--start')) {
    console.log(await evaluate(`(() => {
      const button = [...document.querySelectorAll('button')].find(b => b.textContent.includes('Собрать расширенные предложения'));
      if (!button) throw new Error('Extended collection button not found.');
      if (button.disabled) return 'Collection already running.';
      button.click();
      return 'Fresh partner offer collection started.';
    })()`));
  }
  const result = await evaluate(`(async () => {
    const stored = await chrome.storage.local.get(null);
    const banks = Object.entries(stored).filter(([key]) => key.startsWith('cashflowExtendedHistory:')).map(([, bank]) => ({ ...bank, extendedOffers: bank.offers }));
    return { schemaVersion: 1, generatedAt: new Date().toISOString(), banks,
      progress: [...document.querySelectorAll('.export-message')].map(e => e.textContent),
      running: [...document.querySelectorAll('button')].some(b => b.textContent.includes('Собираю расширенные')) };
  })()`);
  await mkdir('.local', { recursive: true });
  await writeFile('.local/extension-partner-offers.json', JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify({ running: result.running, progress: result.progress, banks: result.banks.map(b => ({ bankId: b.bankId, count: b.offers.length, errors: b.errors })) }));
} finally {
  socket.close();
}
