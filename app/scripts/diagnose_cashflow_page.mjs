const [, , portArg = '9223', urlPrefix, durationArg = '12'] = process.argv;
if (!urlPrefix) {
  throw new Error('Usage: diagnose_cashflow_page.mjs <port> <url-prefix> [duration-seconds]');
}

const targets = await (await fetch(`http://127.0.0.1:${Number(portArg)}/json`)).json();
const target = targets.find(
  (candidate) => candidate.type === 'page' && candidate.url.startsWith(urlPrefix),
);
if (!target) throw new Error(`Page target not found for URL prefix: ${urlPrefix}`);

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

let requestId = 0;
const pending = new Map();
const events = [];
const relevantResponses = [];
const requests = new Map();
socket.onmessage = (event) => {
  const message = JSON.parse(event.data);
  if (message.id) {
    pending.get(message.id)?.(message);
    pending.delete(message.id);
    return;
  }
  if (message.method === 'Network.requestWillBeSent') {
    requests.set(message.params.requestId, {
      method: message.params.request.method,
      postData: message.params.request.postData ?? null,
    });
  } else if (message.method === 'Runtime.exceptionThrown') {
    events.push({ type: 'exception', text: message.params.exceptionDetails?.exception?.description ?? message.params.exceptionDetails?.text });
  } else if (message.method === 'Runtime.consoleAPICalled' && ['error', 'warning'].includes(message.params.type)) {
    events.push({ type: `console.${message.params.type}`, text: message.params.args?.map((arg) => arg.value ?? arg.description).join(' ') });
  } else if (message.method === 'Network.loadingFailed') {
    events.push({ type: 'network.failed', url: message.params.requestId, text: message.params.errorText });
  } else if (message.method === 'Network.responseReceived') {
    if (/cash|bonus|loyal|category|benefit|offer/i.test(message.params.response.url)) {
      relevantResponses.push({
        requestId: message.params.requestId,
        ...requests.get(message.params.requestId),
        status: message.params.response.status,
        mimeType: message.params.response.mimeType,
        url: message.params.response.url,
      });
    }
    if (message.params.response.status >= 400) {
      events.push({ type: 'http', status: message.params.response.status, url: message.params.response.url });
    }
  } else if (message.method === 'Log.entryAdded' && ['error', 'warning'].includes(message.params.entry.level)) {
    events.push({ type: `log.${message.params.entry.level}`, text: message.params.entry.text, url: message.params.entry.url });
  }
};

const send = (method, params = {}) => new Promise((resolve) => {
  const id = ++requestId;
  pending.set(id, resolve);
  socket.send(JSON.stringify({ id, method, params }));
});

await Promise.all([
  send('Runtime.enable'),
  send('Network.enable'),
  send('Log.enable'),
  send('Page.enable'),
]);
await send('Page.reload', { ignoreCache: false });
await new Promise((resolve) => setTimeout(resolve, Number(durationArg) * 1000));
for (const response of relevantResponses) {
  if (!/json/i.test(response.mimeType)) continue;
  const bodyResponse = await send('Network.getResponseBody', { requestId: response.requestId });
  response.body = bodyResponse.result?.body?.slice(0, 100000) ?? null;
}
socket.close();

console.log(JSON.stringify({ url: target.url, events, relevantResponses }, null, 2));
