const [, , portArg = '9223', urlPrefix, selector] = process.argv;

if (!urlPrefix || !selector) {
  throw new Error('Usage: click_cashflow_page.mjs <port> <url-prefix> <selector>');
}

const port = Number(portArg);
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

const expression = `(() => {
  const element = document.querySelector(${JSON.stringify(selector)});
  if (!element) return { clicked: false };
  element.click();
  return {
    clicked: true,
    tag: element.tagName,
    text: element.innerText?.trim().slice(0, 500) || null,
  };
})()`;

const response = await new Promise((resolve, reject) => {
  const id = 1;
  const timeout = setTimeout(() => reject(new Error('CDP click timed out')), 5000);
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
      params: { expression, returnByValue: true },
    }),
  );
});

socket.close();
if (response.result?.exceptionDetails) {
  throw new Error(response.result.exceptionDetails.text);
}
console.log(JSON.stringify(response.result.result.value));
