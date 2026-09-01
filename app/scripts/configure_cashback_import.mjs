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
    tbank: { url: 'https://www.tbank.ru/mybank/bonuses/', matches: ['/mybank/bonuses'], hosts: ['www.tbank.ru', 'id.tbank.ru'] },
    yandex: { url: 'https://sp.yandex.ru/cashback?utm_source=cashflow&utm_medium=extension&retRoute=internal', matches: ['/cashback?', '/cashback/current'], hosts: ['sp.yandex.ru', 'bank.yandex.ru'] },
    alfa: { url: 'https://web.alfabank.ru/marketplace/?loyaltyType=104', matches: ['/marketplace/'], hosts: ['web.alfabank.ru', 'private.auth.alfabank.ru'] },
    sber: { url: 'https://online.sberbank.ru/CSAFront/index.do#/app/loyalty/main/categories/select', matches: ['/loyalty/main/categories', '/CSAFront/index.do#/app/loyalty'], hosts: ['online.sberbank.ru'] },
    ozon: { url: 'https://finance.ozon.ru/lk/favorite-categories-v3?type=current&fromHome=true', matches: ['/lk/favorite-categories', '/lk/cashback', '/lk/bonus'], hosts: ['finance.ozon.ru'] },
    vtb: { url: 'https://online.sbpvtb.ru/home', matches: ['/bonus/categories', '/bonus', '/home'], hosts: ['online.sbpvtb.ru'] },
  })};
  await chrome.storage.local.set({
    cashflowImportRequest: { banks, autoCollect: true, requestedAt: new Date().toISOString() },
  });
  const existing = await chrome.tabs.query({});
  for (const bank of banks) {
    const definition = definitions[bank];
    if (!definition) continue;
    const target = existing.find((tab) =>
      definition.matches.some((route) => tab.url?.includes(route)),
    );
    if (target?.id) {
      await chrome.tabs.reload(target.id);
    } else {
      const bankTab = existing.find((tab) => {
      try { return definition.hosts.includes(new URL(tab.url).hostname); } catch { return false; }
      });
      if (bankTab?.id) {
        await chrome.tabs.update(bankTab.id, { url: definition.url });
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
