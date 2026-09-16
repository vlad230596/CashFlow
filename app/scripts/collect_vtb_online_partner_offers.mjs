import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';
import { saveOfferIcon } from './lib/save-offer-icon.mjs';

const port = Number(process.argv[2] ?? '9223');
const outputPath = resolve(process.argv[3] ?? '.local/vtb-online-partner-offers.json');
const iconDirectory = resolve(dirname(outputPath), 'vtb-online-partner-icons');
const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const target = targets.find((item) => item.type === 'page' && item.url.startsWith('https://online.sbpvtb.ru/'));
if (!target) throw new Error('Open the authenticated VTB Online tab first.');

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
const pause = (ms) => new Promise((done) => setTimeout(done, ms));
async function waitFor(fn, label, ...args) {
  for (let i = 0; i < 100; i++) {
    const result = await evaluate(fn, ...args).catch(() => false);
    if (result) return result;
    await pause(100);
  }
  throw new Error(`Timed out waiting for ${label}`);
}
async function listCards() {
  return evaluate(() => {
    const heading = (text) => [...document.querySelectorAll('h2,h3')]
      .find((item) => item.textContent.trim() === text);
    const partnerSection = heading('От партнеров ВТБ')?.parentElement;
    const moreSection = heading('Еще больше выгоды')?.parentElement?.parentElement;
    const extract = (card, group, index) => {
      const paragraphs = [...card.querySelectorAll('p')].map((item) => item.textContent.trim());
      const background = getComputedStyle(card).backgroundImage;
      return {
        id: `${group}-${index + 1}`,
        group,
        index,
        title: paragraphs[0] || null,
        subtitle: paragraphs[1] || null,
        icon: background !== 'none'
          ? { kind: 'url', value: background.match(/^url\(["']?(.*?)["']?\)$/)?.[1] }
          : card.querySelector('svg')
            ? { kind: 'svg', value: card.querySelector('svg').outerHTML }
            : null,
      };
    };
    const partnerCards = [...(partnerSection?.querySelectorAll('[role="button"]') || [])]
      .map((card, index) => extract(card, 'partners', index));
    const moreCards = [...(moreSection?.querySelectorAll('[role="button"]') || [])]
      .map((card, index) => extract(card, 'more-benefits', index))
      .filter((card) => /\u042f\u043d\u0434\u0435\u043a\u0441|\u043f\u0443\u0442\u0435\u0448\u0435\u0441\u0442\u0432/i.test(`${card.title} ${card.subtitle}`));
    return [...partnerCards, ...moreCards];
  });
}
async function closeSheet() {
  await evaluate(() => document.querySelector('.omega-ui-retail__bottom-sheet [aria-label="Закрыть окно"]')?.click());
}

try {
  await cdp('Page.bringToFront');
  if (await evaluate(() => location.pathname !== '/bonus')) {
    await cdp('Page.navigate', { url: 'https://online.sbpvtb.ru/bonus' });
  }
  await waitFor(() => location.pathname === '/bonus'
    && [...document.querySelectorAll('h3')].some((item) => item.textContent.trim() === 'От партнеров ВТБ'), 'VTB benefits page');
  await evaluate(() => document.querySelector('[role="dialog"] [aria-label="Закрыть"]')?.click());
  await closeSheet();
  const cards = await listCards();
  if (cards.length !== 4 || cards.filter((card) => card.group === 'partners').length !== 3) {
    throw new Error(`Unexpected VTB Online partner card count: ${cards.length}.`);
  }
  const offers = [];
  for (const card of cards) {
    let detailsText = null;
    if (card.group === 'partners') {
      await evaluate((index) => {
        const heading = [...document.querySelectorAll('h3')]
          .find((item) => item.textContent.trim() === 'От партнеров ВТБ');
        heading.parentElement.querySelectorAll('[role="button"]')[index].click();
      }, card.index);
      detailsText = await waitFor(() => document.querySelector('.omega-ui-retail__bottom-sheet')?.innerText,
        `details for ${card.title}`);
      await closeSheet();
    }
    let iconFile = null;
    let iconError = null;
    if (card.icon?.value) {
      try {
        const saved = await saveOfferIcon({ offerId: card.id, icon: card.icon, outputDirectory: iconDirectory });
        iconFile = join(relative(dirname(outputPath), iconDirectory), saved.path).replaceAll('\\', '/');
      } catch (error) { iconError = error.message; }
    }
    offers.push({ ...card, detailsText, iconFile, iconError, sourceUrl: 'https://online.sbpvtb.ru/bonus' });
  }
  const data = { schemaVersion: 1, bankId: 'vtb', source: 'vtb-online-benefits',
    collectedAt: new Date().toISOString(), offers };
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
  console.log(`Saved ${offers.length} VTB Online partner offers, ${offers.filter((item) => item.iconFile).length} icons.`);
} finally {
  socket.close();
}
