import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const port = Number(process.argv[2] ?? '9223');
const outputPath = resolve(process.argv[3] ?? '.local/alfa-partner-offers.json');
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === 'page' && item.url.startsWith('https://web.alfabank.ru/partner-offers/'));
if (!target) throw new Error('Open the authenticated Alfa-Bank partner offers page in Chrome first.');

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

async function waitFor(fn, label, attempts = 60) {
  for (let i = 0; i < attempts; i++) {
    const result = await evaluate(fn).catch(() => false);
    if (result) return result;
    await pause(100);
  }
  throw new Error(`Timed out waiting for ${label}`);
}

async function showCategories() {
  for (let i = 0; i < 5; i++) {
    const state = await evaluate(() => ({
      categories: document.querySelectorAll('[role="dialog"] button[data-test-id="category"]').length,
      back: !!document.querySelector('[role="dialog"] button[data-test-id="side-panel-header-back"]'),
      all: !![...document.querySelectorAll('[data-test-id="categories-carousel"] button')]
        .find((button) => button.textContent.trim() === 'Все категории'),
    }));
    if (state.categories) return;
    if (state.back) {
      await evaluate(() => document.querySelector('[role="dialog"] button[data-test-id="side-panel-header-back"]').click());
    } else if (state.all) {
      await evaluate(() => [...document.querySelectorAll('[data-test-id="categories-carousel"] button')]
        .find((button) => button.textContent.trim() === 'Все категории').click());
    } else {
      throw new Error('Cannot find the Alfa partner categories dialog or its opener.');
    }
    await pause(250);
  }
  await waitFor(() => !!document.querySelector('[role="dialog"] button[data-test-id="category"]'), 'category list');
}

async function save(data) {
  data.collectedAt = new Date().toISOString();
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
}

try {
  await cdp('Page.bringToFront');
  await showCategories();
  const categories = await evaluate(() => [...document.querySelectorAll('[role="dialog"] button[data-test-id="category"]')]
    .map((button) => {
      const lines = button.innerText.split('\n').map((part) => part.trim()).filter(Boolean);
      return { name: lines[0], expectedCount: Number(lines.at(-1)) || 0 };
    }));
  let data;
  try { data = JSON.parse(await readFile(outputPath, 'utf8')); }
  catch { data = { schemaVersion: 1, bankId: 'alfa', sourceUrl: target.url, categories: [], offers: [] }; }
  const offerMap = new Map(data.offers.map((offer) => [offer.id, offer]));
  console.log(`Found ${categories.length} categories.`);

  for (const category of categories) {
    if (data.categories.some((existing) => existing.name === category.name && existing.complete &&
      existing.offerIds.every((id) => !offerMap.get(id)?.details?.rulesButtonPresent || offerMap.get(id)?.details?.rulesUrl))) {
      console.log(`Skipping completed ${category.name}.`);
      continue;
    }
    if (category.expectedCount === 0) {
      data.categories.push({ ...category, foundCount: 0, offerIds: [], complete: true });
      await save(data);
      console.log(`${category.name}: empty.`);
      continue;
    }
    await showCategories();
    await evaluate((name) => {
      const button = [...document.querySelectorAll('[role="dialog"] button[data-test-id="category"]')]
        .find((item) => item.innerText.split('\n')[0].trim() === name);
      if (!button) throw new Error(`Missing category ${name}`);
      button.click();
    }, category.name);
    await waitFor(() => !!document.querySelector('[role="dialog"] [data-test-id="offers-selection-body"]'), `${category.name} offers`);
    await pause(300);
    const cards = await evaluate(() => {
      function idOf(card) {
        const key = Object.keys(card).find((name) => name.startsWith('__reactFiber$'));
        let fiber = key ? card[key] : null;
        for (let i = 0; fiber && i < 12; i++, fiber = fiber.return) {
          const p = fiber.memoizedProps;
          if (p?.offerId) return {
            id: String(p.offerId), name: p.title || null, rateLabel: p.condition || null,
            paymentCondition: p.cashbackCondition || null, expirationDate: p.endDate || null,
            warningText: p.warningText || null, iconUrl: p.iconUrl || null,
          };
        }
        return { id: null, cardText: card.innerText.trim() };
      }
      return [...document.querySelectorAll('[role="dialog"] [data-test-id="offers-selection-body"] button[data-test-id="offer"]')].map(idOf);
    });
    const offerIds = [];
    for (const card of cards) {
      if (!card.id) throw new Error(`Offer without ID in ${category.name}: ${card.cardText}`);
      offerIds.push(card.id);
      const prior = offerMap.get(card.id) || { id: card.id, categories: [] };
      if (!prior.categories.includes(category.name)) prior.categories.push(category.name);
      offerMap.set(card.id, { ...prior, ...card });
      if (prior.details && (!prior.details.rulesButtonPresent || prior.details.rulesUrl)) continue;

      await evaluate((id) => {
        function idOf(element) {
          const key = Object.keys(element).find((name) => name.startsWith('__reactFiber$'));
          let fiber = key ? element[key] : null;
          for (let i = 0; fiber && i < 12; i++, fiber = fiber.return) {
            if (fiber.memoizedProps?.offerId) return String(fiber.memoizedProps.offerId);
          }
          return null;
        }
        const button = [...document.querySelectorAll('[role="dialog"] [data-test-id="offers-selection-body"] button[data-test-id="offer"]')]
          .find((item) => idOf(item) === id);
        if (!button) throw new Error(`Missing offer ${id}`);
        button.click();
      }, card.id);
      await waitFor(() => !!document.querySelector('[role="dialog"] [data-test-id="offer-details-body"]'), `details ${card.id}`);
      await pause(180);
      const details = await evaluate(() => {
        const root = document.querySelector('[role="dialog"] [data-test-id="offer-details-body"]');
        const value = (testId) => root.querySelector(`[data-test-id="${testId}"]`)?.innerText.trim() || null;
        const rulesButton = root.querySelector('[data-test-id="promotion-rules-button"]');
        const key = rulesButton && Object.keys(rulesButton).find((name) => name.startsWith('__reactFiber$'));
        let fiber = key ? rulesButton[key] : null;
        let rulesUrl = null;
        for (let i = 0; fiber && i < 12; i++, fiber = fiber.return) {
          const props = fiber.memoizedProps || {};
          const candidate = props.urlToPdf || props.rulesUrl || props.urlToRules;
          if (typeof candidate === 'string' && /^https?:\/\//.test(candidate)) {
            rulesUrl = candidate;
            break;
          }
        }
        return {
          title: value('offer-title'),
          shortDescription: value('offer-details-short-description'),
          partnerCard: value('offer-details-card'),
          steps: [...root.querySelectorAll('[data-test-id="offer-details-steps"] [data-test-id="cell"]')]
            .map((cell) => cell.innerText.trim()).filter(Boolean),
          terms: value('offer-webview-description'),
          conditions: [...root.querySelectorAll('[data-test-id="condition"]')]
            .map((condition) => condition.innerText.trim()).filter(Boolean),
          partnerDescription: value('partner-description'),
          rulesButtonPresent: !!rulesButton,
          rulesUrl,
        };
      });
      offerMap.set(card.id, { ...offerMap.get(card.id), details: { ...prior.details, ...details } });
      await evaluate(() => document.querySelector('[role="dialog"] button[data-test-id="side-panel-header-back"]')?.click());
      await waitFor(() => !!document.querySelector('[role="dialog"] [data-test-id="offers-selection-body"]'), `return from ${card.id}`);
      await pause(100);
    }
    const complete = offerIds.length === category.expectedCount;
    data.categories = data.categories.filter((item) => item.name !== category.name);
    data.categories.push({ ...category, foundCount: offerIds.length, offerIds, complete });
    data.offers = [...offerMap.values()];
    await save(data);
    console.log(`${category.name}: ${offerIds.length}/${category.expectedCount} offers, ${offerMap.size} unique total.`);
    if (!complete) console.warn(`Count mismatch in ${category.name}; saved for inspection.`);
    await evaluate(() => document.querySelector('[role="dialog"] button[data-test-id="side-panel-header-back"]')?.click());
    await waitFor(() => !!document.querySelector('[role="dialog"] button[data-test-id="category"]'), 'return to categories');
  }
  data.offers = [...offerMap.values()].map((offer) => ({
    ...offer,
    offerType: /скидк/i.test(offer.details?.title || '') ? 'discount'
      : /кэшб|cashback/i.test(`${offer.details?.title || ''} ${offer.details?.terms || ''}`) ? 'cashback'
        : 'other',
  }));
  await save(data);
  console.log(`Saved ${data.offers.length} unique offers to ${outputPath}.`);
} finally {
  socket.close();
}
