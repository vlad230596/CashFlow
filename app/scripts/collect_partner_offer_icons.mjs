import { readFile, writeFile, mkdir, stat } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { saveOfferIcon } from './lib/save-offer-icon.mjs';

const port = Number(process.argv[2] ?? 9223);
const directory = resolve('.local/preview-offer-icons');
await mkdir(directory, { recursive: true });
const indexPath = '.local/partner-offer-icons.json';
const cache = JSON.parse(await readFile(indexPath, 'utf8').catch(() => '{}'));
const offers = JSON.parse(await readFile('assets/partner_offers/offers.json', 'utf8')).offers;
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const ozon = targets.find(t => t.type === 'page' && t.url.startsWith('https://finance.ozon.ru/lk/promotions'));
if (!ozon) throw new Error('Open the Ozon promotions catalogue first.');
const socket = new WebSocket(ozon.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
const icons = await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('Ozon icon scan timed out')), 10000);
  socket.onmessage = ({ data }) => {
    const message = JSON.parse(data);
    if (message.id !== 1) return;
    clearTimeout(timeout);
    if (message.result?.exceptionDetails || message.error) reject(new Error(JSON.stringify(message)));
    else resolve(message.result.result.value);
  };
  socket.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: {
    expression: `(() => [...document.querySelectorAll('[data-testid="go-to-promotion-block"]')].map(card => {
      const logo = card.querySelector('.card-body .logo .image');
      const css = logo ? getComputedStyle(logo).backgroundImage : '';
      return { name: card.querySelector('.card-body-text .title')?.innerText.trim(),
        iconUrl: css.match(/^url\\(["']?(.*?)["']?\\)$/)?.[1] ?? null };
    }))()`, returnByValue: true,
  } }));
});
socket.close();
const ozonUrls = new Map(icons.map(icon => [icon.name, icon.iconUrl]));
const selected = [...new Map(offers.filter(offer => ['sber', 'ozon'].includes(offer.bankId)).map(offer => [`${offer.bankId}:${offer.name}`, offer])).values()];
const sber = targets.find(t => t.type === 'page' && t.url.startsWith('https://online.sberbank.ru/'));
const bankSocket = sber ? new WebSocket(sber.webSocketDebuggerUrl) : null;
if (bankSocket) await new Promise((resolve, reject) => { bankSocket.onopen = resolve; bankSocket.onerror = reject; });
let requestId = 0;
const pending = new Map();
if (bankSocket) bankSocket.onmessage = ({ data }) => {
  const message = JSON.parse(data);
  const request = pending.get(message.id);
  if (!request) return;
  pending.delete(message.id);
  clearTimeout(request.timeout);
  message.error ? request.reject(new Error(JSON.stringify(message.error))) : request.resolve(message.result);
};
function cdp(method, params) {
  return new Promise((resolve, reject) => {
    const id = ++requestId;
    const timeout = setTimeout(() => { pending.delete(id); reject(new Error('Browser logo request timed out')); }, 20000);
    pending.set(id, { resolve, reject, timeout });
    bankSocket.send(JSON.stringify({ id, method, params }));
  });
}
const frameId = bankSocket ? (await cdp('Page.getFrameTree', {})).frameTree.frame.id : null;
async function browserIcon(url) {
  const { resource } = await cdp('Network.loadNetworkResource', { frameId, url, options: { disableCache: false, includeCredentials: false } });
  if (!resource.success || !resource.stream) throw new Error(`Browser logo failed: ${resource.netErrorName ?? resource.httpStatusCode}`);
  let bytes = Buffer.alloc(0);
  try {
    while (true) {
      const chunk = await cdp('IO.read', { handle: resource.stream, size: 262144 });
      bytes = Buffer.concat([bytes, Buffer.from(chunk.data, chunk.base64Encoded ? 'base64' : 'utf8')]);
      if (bytes.length > 5 * 1024 * 1024) throw new Error('Logo too large');
      if (chunk.eof) break;
    }
  } finally { await cdp('IO.close', { handle: resource.stream }); }
  const mime = Object.entries(resource.headers ?? {}).find(([key]) => key.toLowerCase() === 'content-type')?.[1]?.split(';')[0] ?? 'image/png';
  return { kind: 'dataUrl', value: `data:${mime};base64,${bytes.toString('base64')}` };
}
const errors = [];
let position = 0;
async function worker() {
  while (position < selected.length) {
    const offer = selected[position++];
    const key = `${offer.bankId}:${offer.name}`;
    const url = offer.bankId === 'ozon' ? ozonUrls.get(offer.name) : offer.iconUrl;
    if (!url) { errors.push(`${key}: no logo URL`); continue; }
    if (cache[key]?.url === url && await stat(resolve('.local', cache[key].file)).then(() => true, () => false)) continue;
    try {
      let saved;
      try {
        saved = await saveOfferIcon({ offerId: `${offer.bankId}-${offer.name}`, icon: { kind: 'url', value: url }, outputDirectory: directory });
      } catch (error) {
        if (offer.bankId !== 'sber' || !bankSocket || error.cause?.code !== 'SELF_SIGNED_CERT_IN_CHAIN') throw error;
        saved = await saveOfferIcon({ offerId: `${offer.bankId}-${offer.name}`, icon: await browserIcon(url), outputDirectory: directory });
      }
      cache[key] = { url, file: `preview-offer-icons/${saved.path}` };
    } catch (error) { errors.push(`${key}: ${error.message}`); }
  }
}
await Promise.all(Array.from({ length: 6 }, worker));
bankSocket?.close();
await writeFile(indexPath, JSON.stringify(cache, null, 2) + '\n');
console.log(JSON.stringify({ scannedOzon: icons.length, cached: Object.keys(cache).length, errors }));
