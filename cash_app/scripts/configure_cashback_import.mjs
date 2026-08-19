const [, , portArg = '9223', extensionId, banksArg = 'tbank,yandex,alfa,sber,ozon,vtb'] = process.argv;
if (!extensionId) {
  throw new Error('Usage: configure_cashback_import.mjs <port> <extension-id> [banks]');
}

const port = Number(portArg);
const banks = banksArg.split(',').map((value) => value.trim()).filter(Boolean);
const extensionUrl = `chrome-extension://${extensionId}/sidepanel.html`;
const previousTargets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
for (const previousTarget of previousTargets.filter(
  (candidate) => candidate.type === 'page' && candidate.url === extensionUrl,
)) {
  await fetch(`http://127.0.0.1:${port}/json/close/${previousTarget.id}`);
}
const target = await (await fetch(
  `http://127.0.0.1:${port}/json/new?${encodeURIComponent(extensionUrl)}`,
  { method: 'PUT' },
)).json();

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

const expression = `(async () => {
  const banks = ${JSON.stringify(banks)};
  const definitions = ${JSON.stringify({
    tbank: { url: 'https://www.tbank.ru/mybank/bonuses/', match: '/mybank/bonuses', hosts: ['www.tbank.ru', 'id.tbank.ru'] },
    yandex: { url: 'https://sp.yandex.ru/cashback/current?utm_source=cashflow&utm_medium=extension', match: '/cashback/current', hosts: ['sp.yandex.ru', 'bank.yandex.ru'] },
    alfa: { url: 'https://web.alfabank.ru/marketplace/?loyaltyType=104', match: '/marketplace/', hosts: ['web.alfabank.ru', 'private.auth.alfabank.ru'] },
    sber: { url: 'https://online.sberbank.ru/CSAFront/index.do#/app/loyalty/main/categories/select', match: '/loyalty/main/categories', hosts: ['online.sberbank.ru'] },
    ozon: { url: 'https://finance.ozon.ru/lk/cashback', match: '/lk/cashback', hosts: ['finance.ozon.ru'] },
    vtb: { url: 'https://online.sbpvtb.ru/bonus/categories', match: '/bonus/categories', hosts: ['online.sbpvtb.ru'] },
  })};
  await chrome.storage.local.set({
    cashflowImportRequest: { banks, autoCollect: true, requestedAt: new Date().toISOString() },
  });
  const existing = await chrome.tabs.query({});
  for (const bank of banks) {
    const definition = definitions[bank];
    if (!definition) continue;
    const target = existing.find((tab) => tab.url?.includes(definition.match));
    if (target?.id) {
      await chrome.tabs.reload(target.id);
    } else {
      const bankTab = existing.find((tab) => {
      try { return definition.hosts.includes(new URL(tab.url).hostname); } catch { return false; }
      });
      if (bankTab?.id) {
        await chrome.tabs.reload(bankTab.id);
      } else {
        await chrome.tabs.create({ url: definition.url, active: false });
      }
    }
  }
  location.reload();
  return { banks };
})()`;

const result = await new Promise((resolve, reject) => {
  const id = 1;
  const timeout = setTimeout(() => reject(new Error('Configuration timed out')), 10_000);
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    clearTimeout(timeout);
    if (message.result?.exceptionDetails) {
      reject(new Error(message.result.exceptionDetails.text));
    } else {
      resolve(message.result?.result?.value);
    }
  };
  socket.send(JSON.stringify({
    id,
    method: 'Runtime.evaluate',
    params: { expression, awaitPromise: true, returnByValue: true, userGesture: true },
  }));
});

socket.close();
await new Promise((resolve) => setTimeout(resolve, 200));
await fetch(`http://127.0.0.1:${port}/json/close/${target.id}`);
console.log(JSON.stringify(result));
