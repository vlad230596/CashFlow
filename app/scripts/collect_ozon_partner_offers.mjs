import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const positionalArgs = process.argv.slice(2).filter((arg) => !arg.startsWith('--'));
const port = Number(positionalArgs[0] ?? '9223');
const outputPath = resolve(positionalArgs[1] ?? '.local/ozon-partner-offers.json');
const allowConnect = process.argv.includes('--allow-connect');
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === 'page' && item.url.startsWith('https://finance.ozon.ru/'));
if (!target) throw new Error('Open the authenticated Ozon Bank promotions page in Chrome first.');

const socket = new WebSocket(target.webSocketDebuggerUrl);
const pending = new Map();
let nextId = 0;
await new Promise((resolveOpen, reject) => {
  socket.onopen = resolveOpen;
  socket.onerror = reject;
});
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
async function evaluate(fn, ...args) {
  const result = await cdp('Runtime.evaluate', {
    expression: `(${fn.toString()})(...${JSON.stringify(args)})`,
    awaitPromise: true,
    returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  }
  return result.result.value;
}
const pause = (ms) => new Promise((resolveWait) => setTimeout(resolveWait, ms));
async function waitFor(fn, label, attempts = 100, ...args) {
  for (let i = 0; i < attempts; i++) {
    const result = await evaluate(fn, ...args).catch(() => false);
    if (result) return result;
    await pause(100);
  }
  throw new Error(`Timed out waiting for ${label}`);
}
async function save(data) {
  data.collectedAt = new Date().toISOString();
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
}
async function goToList() {
  const path = await evaluate(() => location.pathname);
  if (path === '/lk/promotions') {
    await waitFor(() => !!document.querySelector('[data-testid="promotion-tabs"]'), 'promotions list');
    return;
  }
  if (path === '/lk/promotion') {
    await evaluate(() => history.back());
    const returned = await waitFor(() => location.pathname === '/lk/promotions', 'return to promotions', 25).catch(() => false);
    if (returned) {
      await waitFor(() => !!document.querySelector('[data-testid="promotion-tabs"]'), 'promotions list');
      return;
    }
  }
  await cdp('Page.navigate', { url: 'https://finance.ozon.ru/lk/promotions?filter=all' });
  await waitFor(() => location.pathname === '/lk/promotions'
    && !!document.querySelector('[data-testid="promotion-tabs"]'), 'promotions page reload');
}
async function cardsFromList() {
  return evaluate(() => [...document.querySelectorAll('[data-testid="go-to-promotion-block"]')]
    .map((card, index) => {
      const text = (selector) => card.querySelector(selector)?.innerText.trim() || null;
      const status = text('[data-testid="activate-promo"]');
      return {
        index,
        name: text('.card-body-text .title'),
        category: text('.card-body-text .category'),
        rateLabel: text('.percent'),
        cashbackDescription: text('.image-text .description'),
        expirationLabel: text('.badge'),
        cardText: card.innerText.trim(),
        connectedBefore: status === 'Подключено',
      };
    }));
}

try {
  await cdp('Page.bringToFront');
  await goToList();
  let data;
  try { data = JSON.parse(await readFile(outputPath, 'utf8')); }
  catch {
    data = {
      schemaVersion: 1,
      bankId: 'ozon',
      sourceUrl: 'https://finance.ozon.ru/lk/promotions?filter=all',
      offers: [],
    };
  }
  const tabs = await evaluate(() => [...document.querySelectorAll('[data-testid="promotion-tabs"]')]
    .map((tab) => tab.innerText.trim()));
  const categories = await evaluate(() => [...document.querySelectorAll('[data-testid="category-button"]')]
    .map((button) => button.innerText.trim()));
  const cards = await cardsFromList();
  const allCount = Number(tabs.find((tab) => tab.startsWith('Все'))?.match(/\d+/)?.[0]);
  if (!allCount || cards.length !== allCount) throw new Error(`Catalog count mismatch: ${cards.length}/${allCount}`);
  if (cards.some((card) => !card.name || !card.rateLabel)) throw new Error('A promotion card has no name or rate.');
  data.catalog = { expectedCount: allCount, foundCount: cards.length, categories, initialTabs: tabs };
  await save(data);
  console.log(`Found ${cards.length} Ozon partner cashback offers.`);

  const offerMap = new Map(data.offers.map((offer) => [offer.index, offer]));
  for (const card of cards) {
    const previous = offerMap.get(card.index);
    if (previous?.details && previous.name === card.name && previous.rateLabel === card.rateLabel) continue;
    await goToList();
    const current = await evaluate((index) => {
      const element = [...document.querySelectorAll('[data-testid="go-to-promotion-block"]')][index];
      return element ? {
        name: element.querySelector('.card-body-text .title')?.innerText.trim(),
        rate: element.querySelector('.percent')?.innerText.trim(),
        connected: element.querySelector('[data-testid="activate-promo"]')?.innerText.trim() === 'Подключено',
      } : null;
    }, card.index);
    if (!current || current.name !== card.name || current.rate !== card.rateLabel) {
      throw new Error(`Offer order changed at card ${card.index}: ${card.name}`);
    }
    if (!current.connected && !allowConnect) {
      throw new Error(`Opening ${card.name} may connect it. Rerun with --allow-connect to permit this bank action.`);
    }
    await evaluate((index) => {
      const element = [...document.querySelectorAll('[data-testid="go-to-promotion-block"]')][index];
      element.click();
    }, card.index);
    await waitFor(() => location.pathname === '/lk/promotion'
      && !!document.querySelector('[data-testid="promotion-container"] [data-testid="hero-block-description"]'),
    `details for ${card.name}`);
    await pause(250);
    const details = await evaluate(() => {
      const root = document.querySelector('[data-testid="promotion-container"]');
      const hero = root.querySelector('[data-testid="hero-block-description"]')?.innerText.trim() || null;
      const howTo = root.querySelector('[data-testid="how-to-section"]')?.innerText.trim() || null;
      const about = root.querySelector('[data-testid="about-section"]')?.innerText.trim() || null;
      const recommendations = root.querySelector('[data-testid="same-promotions-section"]');
      const contentText = root.querySelector(':scope > .content')?.innerText || '';
      const beforeRecommendations = recommendations
        ? contentText.split(recommendations.innerText)[0]
        : contentText;
      const termsMatch = beforeRecommendations.match(/(?:^|\n)Условия\s*\n([\s\S]*?)(?=\nО партнёре\s*\n|$)/);
      const links = [...root.querySelectorAll('a[href]')]
        .filter((anchor) => !recommendations?.contains(anchor))
        .map((anchor) => ({ text: anchor.innerText.trim(), url: anchor.href }));
      return {
        url: location.href,
        alias: new URL(location.href).searchParams.get('alias'),
        fullText: `${hero || ''}\n\n${beforeRecommendations}`.trim(),
        hero,
        howTo,
        terms: termsMatch?.[1]?.trim() || null,
        aboutPartner: about,
        links,
        connectedAfterOpening: /Подключено/.test(root.innerText.split('Кешбэк')[0] || ''),
      };
    });
    if (!details.alias || !details.hero || !details.howTo) {
      throw new Error(`Incomplete details for ${card.name}`);
    }
    offerMap.set(card.index, { ...card, connectedBefore: current.connected, details });
    data.offers = [...offerMap.values()].sort((a, b) => a.index - b.index);
    await save(data);
    if ((card.index + 1) % 10 === 0 || card.index + 1 === cards.length) {
      console.log(`Offers: ${card.index + 1}/${cards.length}.`);
    }
  }
  await goToList();
  const finalTabs = await evaluate(() => [...document.querySelectorAll('[data-testid="promotion-tabs"]')]
    .map((tab) => tab.innerText.trim()));
  const finalCards = await cardsFromList();
  data.offers = data.offers.map((offer) => {
    const finalCard = finalCards[offer.index];
    if (finalCard?.name !== offer.name || finalCard?.rateLabel !== offer.rateLabel) {
      throw new Error(`Final catalog order changed at card ${offer.index}`);
    }
    const details = { ...offer.details };
    if (!details.terms) {
      const match = details.fullText.match(/(?:^|\n)(Срок действия[\s\S]*?)(?=\nО партнёре\s*\n|$)/);
      details.terms = match?.[1]?.trim() || null;
    }
    return { ...offer, connectedAtEnd: finalCard.connectedBefore, details };
  });
  data.catalog.finalTabs = finalTabs;
  data.catalog.openingOfferMayConnect = true;
  await save(data);
  console.log(`Saved ${data.offers.length} offers to ${outputPath}.`);
} finally {
  socket.close();
}
