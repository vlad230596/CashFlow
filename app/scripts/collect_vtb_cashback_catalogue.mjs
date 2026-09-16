import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, join, relative, resolve } from 'node:path';
import { saveOfferIcon } from './lib/save-offer-icon.mjs';

const args = process.argv.slice(2);
const rawFileIndex = args.indexOf('--raw-json');
const positionalArgs = args.filter((arg, index) => (rawFileIndex < 0
  || (index !== rawFileIndex && index !== rawFileIndex + 1)) && !arg.startsWith('--'));
const port = Number(positionalArgs[0] ?? '9223');
const outputPath = resolve(positionalArgs[1] ?? '.local/vtb-cashback-catalogue.json');
const imageDirectory = resolve(dirname(outputPath), 'vtb-cashback-images');
const catalogueUrl = 'https://online.sbpvtb.ru/products/cashback/catalogue';
const contentPath = '/msa/api-gw/private/dsls/dsls-content-category/v1/categories';
const imageBase = 'https://h2.sbpvtb.ru';

function item(elements, id) { return elements?.find((entry) => entry.elementId === id); }
function detailItem(elements, prefix) {
  return elements?.find((entry) => entry.elementId?.startsWith(`detailedPage-${prefix}-`));
}
function absoluteImage(url) { return url ? new URL(url, imageBase).toString() : null; }
function normalizeText(value) { return value?.replace(/[\s\u00a0]+/g, ' ').trim() || null; }

async function captureCatalogue() {
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const target = targets.find((entry) => entry.type === 'page'
    && entry.url.startsWith('https://online.sbpvtb.ru/')
    && !new URL(entry.url).pathname.startsWith('/login'));
  if (!target) throw new Error('Open the authenticated VTB Online tab first.');
  const socket = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((done, reject) => { socket.onopen = done; socket.onerror = reject; });
  let nextId = 0;
  const pending = new Map();
  let watchedRequestId = null;
  let resolveBody;
  let rejectBody;
  const bodyPromise = new Promise((resolveResult, reject) => {
    resolveBody = resolveResult;
    rejectBody = reject;
  });
  function cdp(method, params = {}) {
    const id = ++nextId;
    return new Promise((resolveResult, reject) => {
      pending.set(id, { resolve: resolveResult, reject });
      socket.send(JSON.stringify({ id, method, params }));
    });
  }
  socket.onmessage = async ({ data }) => {
    const message = JSON.parse(data);
    if (message.id) {
      const request = pending.get(message.id);
      if (!request) return;
      pending.delete(message.id);
      if (message.error) request.reject(new Error(message.error.message));
      else request.resolve(message.result);
      return;
    }
    if (message.method === 'Network.responseReceived') {
      const url = new URL(message.params.response.url);
      if (url.pathname === contentPath) {
        if (message.params.response.status !== 200) {
          rejectBody(new Error(`VTB catalogue API returned HTTP ${message.params.response.status}.`));
        } else watchedRequestId = message.params.requestId;
      }
    }
    if (message.method === 'Network.loadingFinished' && message.params.requestId === watchedRequestId) {
      try {
        const response = await cdp('Network.getResponseBody', { requestId: watchedRequestId });
        resolveBody(response.base64Encoded
          ? Buffer.from(response.body, 'base64').toString('utf8') : response.body);
      } catch (error) { rejectBody(error); }
    }
  };
  try {
    await cdp('Network.enable');
    await cdp('Page.bringToFront');
    if (new URL(target.url).pathname === '/products/cashback/catalogue') {
      await cdp('Page.reload', { ignoreCache: true });
    } else {
      await cdp('Page.navigate', { url: catalogueUrl });
    }
    const timeoutId = setTimeout(() => rejectBody(new Error('Timed out waiting for VTB catalogue data.')), 30_000);
    try { return JSON.parse(await bodyPromise); }
    finally { clearTimeout(timeoutId); }
  } finally { socket.close(); }
}

function parseCatalogue(raw) {
  const categoriesRaw = raw.locations?.find((location) => location.locationName === 'CASHBACK_PAGE')
    ?.positions?.find((position) => position.positionName === 'CATEGORY')?.categories;
  if (!Array.isArray(categoriesRaw) || categoriesRaw.length < 10) {
    throw new Error('VTB catalogue categories are missing or incomplete.');
  }
  const offers = new Map();
  const categories = categoriesRaw.map((category, index) => {
    const parsedCategory = {
      id: category.categoryCode,
      categoryId: category.categoryId,
      name: normalizeText(item(category.elements, 'heading')?.value),
      order: index,
      imageUrl: absoluteImage(item(category.elements, 'image')?.urlImage),
      imageFile: null,
      offerIds: [],
    };
    for (const product of category.products || []) {
      const elements = product.elements || [];
      const detail = item(elements, 'detailedPage')?.arrayData || [];
      const parsed = {
        id: product.productCode,
        productId: product.productId,
        sourcePath: item(elements, 'body')?.link?.url || null,
        name: normalizeText(item(elements, 'heading')?.value),
        rateLabel: normalizeText(item(elements, 'description')?.value),
        detailTitle: normalizeText(detailItem(detail, 'heading')?.value),
        termsText: detailItem(detail, 'description')?.value?.trim() || null,
        rulesUrl: detailItem(detail, 'secondaryButton')?.link?.url || null,
        shopUrl: detailItem(detail, 'primaryButton')?.link?.url || null,
        iconUrl: absoluteImage(item(elements, 'image')?.urlImage),
        detailImageUrl: absoluteImage(detail.find((entry) => entry.elementType === 'IMAGE' && entry.urlImage)?.urlImage),
        categoryIds: [parsedCategory.id],
        iconFile: null,
        detailImageFile: null,
      };
      if (!parsed.id || !parsed.name || !parsed.rateLabel || !parsed.termsText || !parsed.iconUrl) {
        throw new Error(`Incomplete VTB offer: ${JSON.stringify({ id: parsed.id, name: parsed.name })}`);
      }
      parsedCategory.offerIds.push(parsed.id);
      const previous = offers.get(parsed.id);
      if (previous) {
        for (const key of ['name', 'rateLabel', 'termsText', 'rulesUrl', 'iconUrl', 'sourcePath']) {
          if (previous[key] !== parsed[key]) throw new Error(`Conflicting VTB offer ${parsed.id}: ${key}`);
        }
        previous.categoryIds.push(parsedCategory.id);
      } else offers.set(parsed.id, parsed);
    }
    return parsedCategory;
  });
  return { categories, offers: [...offers.values()] };
}

async function existingFile(offer, field, previous) {
  const file = previous?.[field];
  const urlField = field === 'imageFile' ? 'imageUrl' : field === 'iconFile' ? 'iconUrl' : 'detailImageUrl';
  if (!file || previous[urlField] !== offer[urlField]) return null;
  try { return (await stat(resolve(dirname(outputPath), file))).isFile() ? file : null; }
  catch { return null; }
}
async function saveImage(ownerId, url, previousFile) {
  if (!url) return { file: null, error: null };
  if (previousFile) return { file: previousFile, error: null };
  try {
    const saved = await saveOfferIcon({
      offerId: ownerId,
      icon: { kind: 'url', value: url },
      outputDirectory: imageDirectory,
    });
    return { file: join(relative(dirname(outputPath), imageDirectory), saved.path).replaceAll('\\', '/'), error: null };
  } catch (error) { return { file: null, error: error.message }; }
}

console.log('Reading VTB Online cashback catalogue...');
const raw = rawFileIndex >= 0
  ? JSON.parse(await readFile(resolve(args[rawFileIndex + 1]), 'utf8'))
  : await captureCatalogue();
const data = { schemaVersion: 1, bankId: 'vtb', sourceUrl: catalogueUrl,
  collectedAt: new Date().toISOString(), ...parseCatalogue(raw) };
let previous = null;
try { previous = JSON.parse(await readFile(outputPath, 'utf8')); } catch { /* First run. */ }
const oldCategories = new Map(previous?.categories?.map((category) => [category.id, category]) || []);
const oldOffers = new Map(previous?.offers?.map((offer) => [offer.id, offer]) || []);
async function save() {
  await mkdir(dirname(outputPath), { recursive: true });
  await writeFile(outputPath, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
}
await save();
console.log(`Found ${data.categories.length} categories and ${data.offers.length} unique offers.`);
for (const category of data.categories) {
  const previousFile = await existingFile(category, 'imageFile', oldCategories.get(category.id));
  const result = await saveImage(`category-${category.id}`, category.imageUrl, previousFile);
  category.imageFile = result.file;
  category.imageError = result.error;
}
await save();
for (const [index, offer] of data.offers.entries()) {
  const old = oldOffers.get(offer.id);
  const icon = await saveImage(offer.id, offer.iconUrl, await existingFile(offer, 'iconFile', old));
  offer.iconFile = icon.file;
  offer.iconError = icon.error;
  const detail = await saveImage(`${offer.id}-detail`, offer.detailImageUrl,
    await existingFile(offer, 'detailImageFile', old));
  offer.detailImageFile = detail.file;
  offer.detailImageError = detail.error;
  if ((index + 1) % 10 === 0 || index + 1 === data.offers.length) {
    await save();
    console.log(`Images: ${index + 1}/${data.offers.length} offers.`);
  }
}
await save();
console.log(`Saved VTB catalogue to ${outputPath}.`);
