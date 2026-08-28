const [, , portArg = '9223', extensionId, bankUrlPrefix] = process.argv;

if (!extensionId || !bankUrlPrefix) {
  throw new Error(
    'Usage: probe_cashflow_extension.mjs <port> <extension-id> <bank-url-prefix>',
  );
}

const port = Number(portArg);
const extensionUrl = `chrome-extension://${extensionId}/sidepanel.html`;
const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
const extensionTarget = targets.find(
  (candidate) => candidate.type === 'page' && candidate.url === extensionUrl,
);

if (!extensionTarget) {
  throw new Error(
    'Extension side panel is not open. Run open_cashflow_sidepanel.mjs first.',
  );
}

const socket = new WebSocket(extensionTarget.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

const expression = `(async () => {
  const tabs = await chrome.tabs.query({});
  const matchingTabs = tabs.filter((candidate) => candidate.url?.startsWith(${JSON.stringify(bankUrlPrefix)}));
  if (!matchingTabs.length) throw new Error('Bank tab not found');
  return Promise.all(matchingTabs.map(async (tab) => {
    try {
      return { tabId: tab.id, response: await chrome.tabs.sendMessage(tab.id, { type: 'cashflow:probe-page' }) };
    } catch (error) {
      return { tabId: tab.id, error: String(error) };
    }
  }));
})()`;

const response = await new Promise((resolve, reject) => {
  const id = 1;
  const timeout = setTimeout(() => reject(new Error('Extension probe timed out')), 20000);

  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    clearTimeout(timeout);
    resolve(message);
  };

  socket.send(
    JSON.stringify({
      id,
      method: 'Runtime.evaluate',
      params: { expression, awaitPromise: true, returnByValue: true },
    }),
  );
});

socket.close();

if (response.error) throw new Error(JSON.stringify(response.error));
if (response.result?.exceptionDetails) {
  throw new Error(
    response.result.exceptionDetails.exception?.description ??
      response.result.exceptionDetails.text,
  );
}

console.log(JSON.stringify(response.result.result.value));
