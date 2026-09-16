import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const port = Number(process.argv[2] ?? '9223');
const outputPath = resolve(process.argv[3] ?? '.local/tbank-partner-offers.json');
const detailsOnly = process.argv.includes('--details-only');
const receiptOnly = process.argv.includes('--receipt-only');
const resume = process.argv.includes('--resume');
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) =>
  item.type === 'page' && item.url.startsWith('https://www.tbank.ru/mybank/bonuses/'));
if (!target) throw new Error('Open the authenticated T-Bank bonuses page in Chrome first.');

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
  const expression = `(${fn.toString()})(...${JSON.stringify(args)})`;
  const result = await cdp('Runtime.evaluate', {
    expression, awaitPromise: true, returnByValue: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description ?? result.exceptionDetails.text);
  }
  return result.result.value;
}
async function navigate(path, selector) {
  const url = `https://www.tbank.ru${path}`;
  await cdp('Page.navigate', { url });
  for (let attempt = 0; attempt < 100; attempt++) {
    const state = await evaluate((expected, query) => ({
      url: location.href,
      ready: location.href.startsWith(expected) && Boolean(document.querySelector(query)),
    }), url, selector).catch(() => null);
    if (state?.ready) return;
    if (attempt > 10 && state?.url?.startsWith('https://id.tbank.ru/')) {
      throw new Error('AUTH_REQUIRED');
    }
    await new Promise((resolveWait) => setTimeout(resolveWait, 100));
  }
  throw new Error(`Timed out loading ${path}`);
}

async function collectCategoryCards(delay) {
  const seen = new Map();
  const selector = '[data-qa-type^="desktop-bonuses-category-list-offer-"]';
  const scan = () => {
    for (const card of document.querySelectorAll(selector)) {
      const qa = card.getAttribute('data-qa-type') || '';
      if (!/^desktop-bonuses-category-list-offer-\d+$/.test(qa)) continue;
      const fiberKey = Object.keys(card).find((key) => key.startsWith('__reactFiber$'));
      let fiber = fiberKey ? card[fiberKey] : null;
      while (fiber && !fiber.memoizedProps?.offer?.offerId) fiber = fiber.return;
      const offer = fiber?.memoizedProps?.offer;
      if (!offer?.offerId) continue;
      seen.set(offer.offerId, {
        id: offer.offerId,
        name: offer.merchantName || null,
        merchantId: offer.merchantId || null,
        title: offer.title || null,
        subtitle: offer.subtitle || null,
        expirationLabel: offer.expirationText || null,
        merchantSubtitle: offer.merchantSubcategory || null,
        url: new URL(offer.link, location.origin).href,
        iconUrl: offer.logo || null,
        imageUrl: offer.image || null,
        offerType: offer.offerType || null,
      });
    }
  };
  const height = document.documentElement.scrollHeight;
  const step = Math.max(400, Math.floor(window.innerHeight * 0.6));
  for (let y = 0; y <= height; y += step) {
    window.scrollTo({ top: y, behavior: 'instant' });
    window.dispatchEvent(new Event('scroll'));
    document.dispatchEvent(new Event('scroll'));
    await new Promise((resolveWait) => setTimeout(resolveWait, delay));
    scan();
  }
  window.scrollTo({ top: height, behavior: 'instant' });
  window.dispatchEvent(new Event('scroll'));
  document.dispatchEvent(new Event('scroll'));
  await new Promise((resolveWait) => setTimeout(resolveWait, delay));
  scan();
  return [...seen.values()];
}

try {
  let categoryResults = [];
  let cashbackOffers = [];
  let unclassifiedOffers = [];
  let previousOffers = [];
  if (detailsOnly) {
    const previous = JSON.parse(await readFile(outputPath, 'utf8'));
    categoryResults = previous.categories;
    cashbackOffers = previous.offers;
    previousOffers = previous.offers;
    unclassifiedOffers = previous.unclassifiedOffers;
    if (receiptOnly) cashbackOffers = cashbackOffers.filter((offer) => offer.offerType === 'RECEIPT');
    if (resume) cashbackOffers = cashbackOffers.filter((offer) => offer.detailVersion !== 2);
    console.log(`Refreshing details for ${cashbackOffers.length} cashback offers.`);
  } else {
  await navigate('/mybank/bonuses/category/all/', '[data-qa-type="desktop-bonuses-all-categories"]');
  const categoryButtons = await evaluate(() =>
    [...document.querySelectorAll('[data-qa-type^="desktop-bonuses-all-categories-category-"]')]
      .map((button) => ({
        qa: button.getAttribute('data-qa-type'),
        name: button.querySelector('h6')?.textContent?.trim() || null,
        expectedCount: Number(button.querySelectorAll('h6')[1]?.textContent) || null,
      })),
  );
  const categories = [];
  for (const button of categoryButtons) {
    await navigate('/mybank/bonuses/category/all/', `[data-qa-type="${button.qa}"]`);
    const path = await evaluate(async (qa) => {
      document.querySelector(`[data-qa-type="${qa}"]`)?.click();
      for (let i = 0; i < 50; i++) {
        if (location.pathname.includes('/bonuses/categories/')) return location.pathname;
        await new Promise((resolveWait) => setTimeout(resolveWait, 50));
      }
      return null;
    }, button.qa);
    if (!path) throw new Error(`Could not open category ${button.name}`);
    categories.push({ ...button, path });
  }
  console.log(`Found ${categories.length} partner categories.`);

  const offerMap = new Map();
  for (const category of categories) {
    await navigate(category.path, '[data-qa-type="desktop-bonuses-category-list"]');
    await cdp('Page.bringToFront');
    let result = await evaluate(collectCategoryCards, 180);
    if (category.expectedCount && result.length < category.expectedCount) {
      result = await evaluate(collectCategoryCards, 450);
    }
    const offerIds = [];
    for (const offer of result) {
      offerIds.push(offer.id);
      if (!offerMap.has(offer.id)) offerMap.set(offer.id, offer);
    }
    categoryResults.push({
      name: category.name,
      path: category.path,
      expectedCount: category.expectedCount,
      collectedCount: result.length,
      offerIds,
    });
    console.log(`${category.name}: ${result.length}/${category.expectedCount ?? '?'} offers`);
  }

  cashbackOffers = [...offerMap.values()].filter((offer) => /к[еэ]шб[еэ]к/i.test(offer.title ?? ''));
  unclassifiedOffers = [...offerMap.values()].filter((offer) => !/к[еэ]шб[еэ]к/i.test(offer.title ?? ''));
  console.log(`Found ${offerMap.size} distinct offers, ${cashbackOffers.length} with cashback.`);
  }
  const details = new Map((detailsOnly ? previousOffers : cashbackOffers)
    .map((offer) => [offer.id, offer]));
  const save = async () => {
    const result = {
      schemaVersion: 1,
      bankId: 'tbank',
      collectedAt: new Date().toISOString(),
      categories: categoryResults,
      offers: [...details.values()],
      unclassifiedOffers,
    };
    await mkdir(resolve(outputPath, '..'), { recursive: true });
    await writeFile(outputPath, JSON.stringify(result, null, 2), 'utf8');
  };
  await save();
  for (const [index, offer] of cashbackOffers.entries()) {
    try {
      await navigate(new URL(offer.url).pathname + '/', '[data-qa-type="desktop-bonuses-offer"]');
      const detail = await evaluate(() => {
        const text = (value) => value?.textContent?.replace(/\s+/g, ' ').trim() || null;
        const visibleText = (value) => value?.innerText?.replace(/\s*\n+\s*/g, '\n').trim() || null;
        const steps = [...document.querySelectorAll('[data-qa-type^="desktop-bonuses-offer-steps__step-"]')]
          .filter((item) => /^desktop-bonuses-offer-steps__step-\d+$/.test(item.getAttribute('data-qa-type') || ''))
          .map(visibleText).filter(Boolean);
        const receiptRules = [...document.querySelectorAll('[data-qa-type^="desktop-bonuses-receipt-steps__step"]')]
          .filter((item) => /^desktop-bonuses-receipt-steps__step\d+$/.test(item.getAttribute('data-qa-type') || ''))
          .map((item) => ({
            name: text(item.querySelector('[data-qa-type$="-title-text"]')),
            value: visibleText(item.querySelector('[data-qa-type$="-description"]')),
          })).filter((rule) => rule.name || rule.value);
        return {
          name: text(document.querySelector('[data-qa-type="atom-desktop-title-title"]')),
          cardText: visibleText(document.querySelector('[data-qa-type="desktop-bonuses-offer-card"]')),
          subtitle: text(document.querySelector('[data-qa-type="desktop-bonuses-offer-subtitle"]')),
          expirationLabel: text(document.querySelector('[data-qa-type="desktop-bonuses-offer-expiration"]')),
          steps,
          receiptRules,
          otherConditions: visibleText(document.querySelector('[data-qa-type="desktop-bonuses-offer-steps__other-conditions"]'))
            || visibleText(document.querySelector('[data-qa-type="desktop-bonuses-receipt-steps__other-conditions"]')),
          partnerDescription: visibleText(document.querySelector('[data-qa-type="desktop-bonuses-partner-info-description"]')),
          productDescription: visibleText(document.querySelector('[data-qa-type="desktop-bonuses-offer-product-info-skeleton-description"]')),
        };
      });
      details.set(offer.id, { ...offer, ...detail, detailVersion: 2, error: null });
    } catch (error) {
      if (String(error).includes('AUTH_REQUIRED')) {
        console.log('T-Bank requested a new login; progress is saved.');
        break;
      }
      details.set(offer.id, { ...offer, error: String(error) });
    }
    if ((index + 1) % 25 === 0) {
      await save();
      console.log(`Details: ${index + 1}/${cashbackOffers.length}`);
    }
  }
  await save();
  console.log(`Saved ${details.size} cashback offers to ${outputPath}`);
} finally {
  socket.close();
}
