import { createHash } from 'node:crypto';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';
import { saveOfferIcon } from './lib/save-offer-icon.mjs';

const port = Number(process.argv[2] ?? '9223');
const outputPath = resolve(process.argv[3] ?? '.local/yandex-partner-offers.json');
const imageDirectory = resolve(dirname(outputPath), 'yandex-partner-images');
const sourceUrl = 'https://bank.yandex.ru/webview-sdk/partners/cashback';
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === 'page' && item.url.startsWith(sourceUrl));
if (!target) throw new Error('Open the Yandex Pay partner cashback page first.');

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((done, reject) => { socket.onopen = done; socket.onerror = reject; });
let nextId = 0;
const pending = new Map();
socket.onmessage = ({ data }) => {
  const message = JSON.parse(data);
  const request = pending.get(message.id);
  if (!request) return;
  pending.delete(message.id);
  if (message.error) request.reject(new Error(message.error.message));
  else request.resolve(message.result);
};
function cdp(method, params = {}) {
  const id = ++nextId;
  return new Promise((resolveResult, reject) => {
    pending.set(id, { resolve: resolveResult, reject });
    socket.send(JSON.stringify({ id, method, params }));
  });
}
async function evaluate(fn) {
  const result = await cdp('Runtime.evaluate', {
    expression: `(${fn.toString()})()`,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  }
  return result.result.value;
}
function unwrapCssUrl(value) { return value?.match(/^url\(["']?(.*?)["']?\)$/)?.[1] || null; }
function stableId(name, merchantUrl) {
  return `partner-${createHash('sha256').update(`${name}\n${merchantUrl}`).digest('hex').slice(0, 14)}`;
}
async function readProgramTerms() {
  const tab = targets.find((item) => item.type === 'page'
    && item.url.startsWith('https://sp.yandex.ru/cashback'));
  if (!tab) return null;
  const peer = new WebSocket(tab.webSocketDebuggerUrl);
  await new Promise((done, reject) => { peer.onopen = done; peer.onerror = reject; });
  let timeoutId;
  try {
    return await Promise.race([
      new Promise((done) => {
        peer.onmessage = ({ data }) => {
          const message = JSON.parse(data);
          if (message.id === 1) done(message.result?.result?.value || null);
        };
        peer.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: {
          expression: `(() => { const section=document.querySelector('[data-test-id="globalCashbackCalculated:legal"]'); return section ? { text:section.innerText.trim(), rulesUrl:section.querySelector('a')?.href || null, sourceUrl:location.origin+location.pathname } : null; })()`,
          returnByValue: true,
        } }));
      }),
      new Promise((done) => { timeoutId = setTimeout(() => done(null), 3_000); }),
    ]);
  } finally { clearTimeout(timeoutId); peer.close(); }
}
async function fileStillValid(previous, field, sourceField, currentSource) {
  if (!previous?.[field] || previous[sourceField] !== currentSource) return null;
  try { return (await stat(resolve(dirname(outputPath), previous[field]))).isFile() ? previous[field] : null; }
  catch { return null; }
}
async function saveImage(id, url, previousFile) {
  if (!url) return { file: null, error: null };
  if (previousFile) return { file: previousFile, error: null };
  try {
    const saved = await saveOfferIcon({
      offerId: id,
      icon: { kind: 'url', value: url },
      outputDirectory: imageDirectory,
    });
    return { file: join(relative(dirname(outputPath), imageDirectory), saved.path).replaceAll('\\', '/'), error: null };
  } catch (error) { return { file: null, error: error.message }; }
}

try {
  await cdp('Page.bringToFront');
  let snapshot;
  for (let attempt = 0; attempt < 50; attempt++) {
    snapshot = await evaluate(() => {
      const grid = [...document.querySelectorAll('div')]
        .find((element) => element.className?.includes?.('grid-cols-2')
          && element.querySelectorAll(':scope > div.w-full').length > 10);
      if (!grid) return null;
      const cssUrl = (element) => element?.style?.backgroundImage || null;
      return {
        pageTitle: document.querySelector('h1')?.textContent?.trim() || document.title,
        introText: document.body.innerText.split('\n').map((line) => line.trim()).find((line) => line.includes('Get Plus points')) || null,
        cards: [...grid.children].map((card, index) => {
          const paragraphs = [...card.querySelectorAll('p')].map((item) => item.textContent.trim());
          const link = card.querySelector('a[aria-label]');
          const iconElement = card.querySelector('[class*="RoundPicture-module__"][style*="background-image"]');
          const artworkElement = card.querySelector('[aria-hidden="true"][style*="background-image"]');
          const rateLabel = card.innerText.trim().split(/\n+/)[0].trim();
          return {
            index,
            name: paragraphs[0] || null,
            rateLabel,
            description: paragraphs[1] || null,
            deeplinkUrl: link?.getAttribute('href') || null,
            iconCss: cssUrl(iconElement),
            artworkCss: cssUrl(artworkElement),
            hasSplitBadge: !![...card.querySelectorAll('[style*="background-image"]')]
              .find((element) => element.style.backgroundImage.includes('split-merchant-icon')),
          };
        }),
      };
    });
    if (snapshot?.cards?.length > 10) break;
    await new Promise((done) => setTimeout(done, 100));
  }
  if (!snapshot?.cards || snapshot.cards.length < 15) {
    throw new Error(`Incomplete Yandex partner catalogue: ${snapshot?.cards?.length || 0} cards.`);
  }
  const offers = snapshot.cards.map((card) => {
    const merchantUrl = card.deeplinkUrl ? new URL(card.deeplinkUrl).searchParams.get('url') : null;
    const iconUrl = unwrapCssUrl(card.iconCss);
    const artworkUrl = unwrapCssUrl(card.artworkCss);
    if (!card.name || !/^\d+(?:[.,]\d+)?%$/.test(card.rateLabel) || !merchantUrl || !iconUrl || !artworkUrl) {
      throw new Error(`Incomplete Yandex partner card: ${JSON.stringify({ name: card.name, rate: card.rateLabel })}`);
    }
    return {
      id: stableId(card.name, new URL(merchantUrl).hostname),
      name: card.name,
      rateLabel: card.rateLabel,
      percent: Number(card.rateLabel.replace('%', '').replace(',', '.')),
      description: card.description,
      deeplinkUrl: card.deeplinkUrl,
      merchantUrl,
      iconUrl,
      artworkUrl,
      hasSplitBadge: card.hasSplitBadge,
      iconFile: null,
      artworkFile: null,
    };
  });
  if (new Set(offers.map((offer) => offer.id)).size !== offers.length) {
    throw new Error('Duplicate Yandex partner offer IDs.');
  }
  let previous = null;
  try { previous = JSON.parse(await readFile(outputPath, 'utf8')); } catch { /* First run. */ }
  const oldOffers = new Map(previous?.offers?.map((offer) => [offer.id, offer]) || []);
  const data = { schemaVersion: 1, bankId: 'yandex', sourceUrl,
    collectedAt: new Date().toISOString(), pageTitle: snapshot.pageTitle,
    introText: snapshot.introText, programTerms: await readProgramTerms(), offers };
  async function save() {
    await mkdir(dirname(outputPath), { recursive: true });
    await writeFile(outputPath, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
  }
  await save();
  for (const [index, offer] of offers.entries()) {
    const old = oldOffers.get(offer.id);
    const icon = await saveImage(offer.id, offer.iconUrl,
      await fileStillValid(old, 'iconFile', 'iconUrl', offer.iconUrl));
    offer.iconFile = icon.file;
    offer.iconError = icon.error;
    const artwork = await saveImage(`${offer.id}-artwork`, offer.artworkUrl,
      await fileStillValid(old, 'artworkFile', 'artworkUrl', offer.artworkUrl));
    offer.artworkFile = artwork.file;
    offer.artworkError = artwork.error;
    if ((index + 1) % 5 === 0 || index + 1 === offers.length) {
      await save();
      console.log(`Yandex partner images: ${index + 1}/${offers.length}.`);
    }
  }
  await save();
  console.log(`Saved ${offers.length} Yandex Pay partner offers to ${outputPath}.`);
} finally { socket.close(); }
