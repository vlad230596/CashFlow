import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';

const port = Number(process.argv[2] ?? '9223');
const outputPath = resolve(process.argv[3] ?? '.local/sber-partner-offers.json');
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === 'page' && item.url.startsWith('https://online.sberbank.ru/'));
if (!target) throw new Error('Open the authenticated SberBank Online page in Chrome first.');

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
async function waitFor(fn, label, attempts = 80, ...args) {
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

async function closeDetailDialogs() {
  for (let i = 0; i < 12; i++) {
    const closed = await evaluate(() => {
      const dialogs = [...document.querySelectorAll('[role="dialog"]')];
      const button = [...(dialogs.at(-1)?.querySelectorAll('button') || [])]
        .find((item) => item.innerText.trim() === 'Понятно');
      if (button) button.click();
      return !!button;
    });
    if (!closed) return;
    await pause(50);
  }
}

async function goToDirectory() {
  await closeDetailDialogs();
  for (let i = 0; i < 5; i++) {
    const path = await evaluate(() => location.pathname);
    if (path.endsWith('/partners')) {
      await waitFor(() => !!document.querySelector('main a[href*="/app/loyalty/main/partner?id="]'), 'partner directory');
      return;
    }
    if (path.endsWith('/partner') || path.endsWith('/offer') || path.endsWith('/offers')) {
      await evaluate(() => document.querySelector('main button[aria-label="Вернуться назад"]')?.click());
    } else if (path.endsWith('/main')) {
      await evaluate(() => [...document.querySelectorAll('main button')]
        .find((item) => item.innerText.includes('Магазины и сервисы'))?.click());
    } else {
      throw new Error(`Unexpected SberBank route: ${path}`);
    }
    await pause(350);
  }
  throw new Error('Cannot reach the Sber partner directory.');
}

async function revealAllPartners() {
  const steps = [];
  for (let j = 0; j < 30; j++) {
    const state = await evaluate(() => ({
      count: document.querySelectorAll('main a[href*="/app/loyalty/main/partner?id="]').length,
      more: !![...document.querySelectorAll('main button')].find((item) => item.innerText.trim() === 'Показать ещё'),
    }));
    if (!state.more) return steps;
    await evaluate(() => [...document.querySelectorAll('main button')]
      .find((item) => item.innerText.trim() === 'Показать ещё')?.click());
    await waitFor((previous) => document.querySelectorAll('main a[href*="/app/loyalty/main/partner?id="]').length > previous
      || ![...document.querySelectorAll('main button')].some((item) => item.innerText.trim() === 'Показать ещё'),
    `more partners after ${state.count}`, 50, state.count);
    steps.push(state.count);
  }
  throw new Error('Partner directory still has a Show more button after 30 clicks.');
}

async function directoryCards() {
  return evaluate(() => [...document.querySelectorAll('main a[href*="/app/loyalty/main/partner?id="]')]
    .map((anchor) => {
      const href = anchor.getAttribute('href');
      const lines = anchor.innerText.split('\n').map((part) => part.trim()).filter(Boolean);
      return {
        id: new URL(href, location.origin).searchParams.get('id'),
        href,
        name: anchor.querySelector('img')?.alt || lines.at(-1) || null,
        rateLabel: lines.find((part) => /%|бонус/i.test(part)) || null,
        cardText: anchor.innerText.trim(),
        iconUrl: anchor.querySelector('img')?.getAttribute('src') || null,
      };
    }));
}

async function expandPartnerDetail() {
  // Each click reveals more rate cards; some partners have none.
  for (let i = 0; i < 15; i++) {
    const clicked = await evaluate(() => {
      const button = [...document.querySelectorAll('main button')]
        .find((item) => item.innerText.trim() === 'Показать ещё');
      button?.click();
      return !!button;
    });
    if (!clicked) break;
    await pause(100);
  }
}

async function collectPartnerDetail() {
  await expandPartnerDetail();
  let fullConditions = null;
  const hasConditionsDialog = await evaluate(() => {
    const button = [...document.querySelectorAll('main button')]
      .find((item) => item.innerText.trim() === 'Показать все');
    button?.click();
    return !!button;
  });
  if (hasConditionsDialog) {
    await waitFor(() => [...document.querySelectorAll('[role="dialog"]')]
      .some((dialog) => dialog.innerText.includes('Условия партнёра')), 'full partner conditions');
    fullConditions = await evaluate(() => [...document.querySelectorAll('[role="dialog"]')]
      .find((dialog) => dialog.innerText.includes('Условия партнёра'))?.innerText.trim() || null);
    await closeDetailDialogs();
  }
  const detail = await evaluate(() => {
    const main = document.querySelector('main');
    const links = [...main.querySelectorAll('a')]
      .filter((anchor) => anchor.innerText.trim() && anchor.getAttribute('href'))
      .map((anchor) => {
        const raw = anchor.getAttribute('href');
        const normalized = raw.replace(/^https:\/(?!\/)/, 'https://').replace(/^http:\/(?!\/)/, 'http://');
        return { text: anchor.innerText.trim(), url: normalized };
      })
      .filter((link) => !link.url.startsWith('/'));
    const rateButtons = [...main.querySelectorAll('button')]
      .filter((button) => button.innerText.includes('Показать подробнее'))
      .map((button) => button.innerText.trim());
    return {
      text: main.innerText.replace(/^Назад\s*/, '').trim(),
      links,
      rateButtons,
    };
  });
  const rateDetails = [];
  for (let i = 0; i < detail.rateButtons.length; i++) {
    await evaluate((index) => [...document.querySelectorAll('main button')]
      .filter((button) => button.innerText.includes('Показать подробнее'))[index]?.click(), i);
    await waitFor(() => [...document.querySelectorAll('[role="dialog"]')]
      .some((dialog) => dialog.innerText.includes('Понятно')), `rate details ${i}`);
    const text = await evaluate(() => [...document.querySelectorAll('[role="dialog"]')]
      .at(-1)?.innerText.trim() || null);
    rateDetails.push({ cardText: detail.rateButtons[i], text });
    await closeDetailDialogs();
  }
  return { ...detail, fullConditions, rateDetails };
}

async function goToOffers() {
  await closeDetailDialogs();
  for (let i = 0; i < 5; i++) {
    const path = await evaluate(() => location.pathname);
    if (path.endsWith('/offers')) {
      await waitFor(() => !!document.querySelector('main a[href*="/app/loyalty/main/offer?id="]'), 'promotions');
      return;
    }
    if (path.endsWith('/offer') || path.endsWith('/partners') || path.endsWith('/partner')) {
      await evaluate(() => document.querySelector('main button[aria-label="Вернуться назад"]')?.click());
    } else if (path.endsWith('/main')) {
      await evaluate(() => document.querySelector('main button[aria-label="Акции"]')?.click());
    } else {
      throw new Error(`Unexpected SberBank route: ${path}`);
    }
    await pause(350);
  }
  throw new Error('Cannot reach the Sber promotions page.');
}

try {
  await cdp('Page.bringToFront');
  let data;
  try { data = JSON.parse(await readFile(outputPath, 'utf8')); }
  catch { data = { schemaVersion: 1, bankId: 'sber', sourceUrl: 'https://online.sberbank.ru/app/loyalty/main/partners', directory: {}, partners: [], promotions: [] }; }
  await goToDirectory();
  const expansionSteps = await revealAllPartners();
  const rawCards = await directoryCards();
  const cardMap = new Map();
  for (const card of rawCards) {
    if (!card.id) throw new Error('Partner directory has a card without an ID.');
    const existing = cardMap.get(card.id);
    const appearance = { rateLabel: card.rateLabel, cardText: card.cardText };
    if (existing) existing.appearances.push(appearance);
    else cardMap.set(card.id, { ...card, appearances: [appearance] });
  }
  const cards = [...cardMap.values()];
  const ids = cards.map((card) => card.id);
  data.directory = { foundCount: rawCards.length, uniquePartnerCount: cards.length, fullyExpanded: true, expansionSteps, partnerIds: ids };
  await save(data);
  console.log(`Found ${cards.length} Sber partners.`);

  const partnerMap = new Map(data.partners.map((partner) => [partner.id, partner]));
  for (let index = 0; index < cards.length; index++) {
    const card = cards[index];
    if (partnerMap.get(card.id)?.details) continue;
    await goToDirectory();
    for (let i = 0; i < 10; i++) {
      const visible = await evaluate((href) => !!document.querySelector(`main a[href="${href}"]`), card.href);
      if (visible) break;
      const clicked = await evaluate(() => {
        const button = [...document.querySelectorAll('main button')]
          .find((item) => item.innerText.trim() === 'Показать ещё');
        button?.click();
        return !!button;
      });
      if (!clicked) throw new Error(`Cannot reveal partner ${card.id}`);
      await pause(180);
    }
    await evaluate((href) => {
      const anchor = document.querySelector(`main a[href="${href}"]`);
      if (!anchor) throw new Error(`Missing partner link ${href}`);
      anchor.click();
    }, card.href);
    await waitFor((id) => location.pathname.endsWith('/partner') && new URL(location.href).searchParams.get('id') === id
      && !!document.querySelector('main section'), `partner ${card.id}`, 80, card.id);
    await pause(250);
    const details = await collectPartnerDetail();
    partnerMap.set(card.id, { ...card, details });
    data.partners = [...partnerMap.values()];
    await save(data);
    if ((index + 1) % 10 === 0 || index + 1 === cards.length) console.log(`Partners: ${index + 1}/${cards.length}.`);
  }

  await goToOffers();
  const promotionCards = await evaluate(() => [...document.querySelectorAll('main a[href*="/app/loyalty/main/offer?id="]')]
    .map((anchor) => {
      const href = anchor.getAttribute('href');
      return {
        id: new URL(href, location.origin).searchParams.get('id'),
        href,
        cardText: anchor.innerText.trim(),
        partnerName: anchor.querySelector('img')?.alt || null,
        iconUrl: anchor.querySelector('img')?.getAttribute('src') || null,
      };
    }));
  const promotionMap = new Map(data.promotions.map((promotion) => [promotion.id, promotion]));
  for (const card of promotionCards) {
    if (promotionMap.get(card.id)?.details) continue;
    await goToOffers();
    await evaluate((href) => document.querySelector(`main a[href="${href}"]`)?.click(), card.href);
    await waitFor((id) => location.pathname.endsWith('/offer') && new URL(location.href).searchParams.get('id') === id
      && !!document.querySelector('main section'), `promotion ${card.id}`, 80, card.id);
    await pause(200);
    const details = await evaluate(() => {
      const main = document.querySelector('main');
      return {
        text: main.innerText.replace(/^Назад\s*/, '').trim(),
        links: [...main.querySelectorAll('a')]
          .filter((anchor) => anchor.innerText.trim() && anchor.getAttribute('href'))
          .map((anchor) => {
            const raw = anchor.getAttribute('href');
            return { text: anchor.innerText.trim(), url: raw.replace(/^https:\/(?!\/)/, 'https://') };
          }).filter((link) => !link.url.startsWith('/')),
      };
    });
    promotionMap.set(card.id, { ...card, details });
    data.promotions = [...promotionMap.values()];
    await save(data);
  }
  await goToOffers();
  data.partners = [...partnerMap.values()].map((partner) => ({
    ...partner,
    partnerCategory: partner.details?.text?.split('\n').map((part) => part.trim()).find(Boolean) || null,
  }));
  data.promotions = [...promotionMap.values()];
  await save(data);
  console.log(`Saved ${data.partners.length} partners and ${data.promotions.length} promotions to ${outputPath}.`);
} finally {
  socket.close();
}
