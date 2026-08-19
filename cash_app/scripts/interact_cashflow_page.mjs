const [, , portArg = '9223', urlPrefix, action = 'hover', selector, indexArg = '0'] =
  process.argv;

if (!urlPrefix || !selector || !['hover', 'click'].includes(action)) {
  throw new Error(
    'Usage: interact_cashflow_page.mjs <port> <url-prefix> <hover|click> <selector> [index]',
  );
}

const port = Number(portArg);
const index = Number(indexArg);
const targets = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
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
socket.onmessage = (event) => {
  const message = JSON.parse(event.data);
  const handler = pending.get(message.id);
  if (!handler) return;
  pending.delete(message.id);
  handler(message);
};
const send = (method, params = {}) =>
  new Promise((resolve) => {
    const id = ++requestId;
    pending.set(id, resolve);
    socket.send(JSON.stringify({ id, method, params }));
  });

const expression = `(() => {
  const element = document.querySelectorAll(${JSON.stringify(selector)})[${index}];
  if (!element) return null;
  element.scrollIntoView({ block: 'center', inline: 'center' });
  const rect = element.getBoundingClientRect();
  return {
    x: rect.left + rect.width / 2,
    y: rect.top + rect.height / 2,
    text: element.innerText?.trim().slice(0, 500) || null,
  };
})()`;
const evaluated = await send('Runtime.evaluate', { expression, returnByValue: true });
const point = evaluated.result?.result?.value;
if (!point) throw new Error('Target element not found');

await send('Input.dispatchMouseEvent', {
  type: 'mouseMoved',
  x: point.x,
  y: point.y,
});
if (action === 'click') {
  await send('Input.dispatchMouseEvent', {
    type: 'mousePressed',
    x: point.x,
    y: point.y,
    button: 'left',
    clickCount: 1,
  });
  await send('Input.dispatchMouseEvent', {
    type: 'mouseReleased',
    x: point.x,
    y: point.y,
    button: 'left',
    clickCount: 1,
  });
}

socket.close();
console.log(JSON.stringify({ action, ...point }));
