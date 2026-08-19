const [, , portArg = '9223', urlPrefix, selector = 'button', textValue, indexArg = '0'] =
  process.argv;

if (!urlPrefix || !textValue) {
  throw new Error(
    'Usage: click_cashflow_text.mjs <port> <url-prefix> <selector> <exact-text>',
  );
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

const expression = `(() => {
  const normalize = (value) => value?.replace(/\\s+/g, ' ').trim() || '';
  const element = Array.from(document.querySelectorAll(${JSON.stringify(selector)}))
    .filter((candidate) => normalize(candidate.innerText || candidate.getAttribute('aria-label')) === ${JSON.stringify(textValue)})[${Number(indexArg)}];
  if (!element) return { clicked: false };
  element.scrollIntoView({ block: 'center', inline: 'center' });
  element.click();
  return { clicked: true, tag: element.tagName, text: normalize(element.innerText) };
})()`;

const response = await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('CDP click timed out')), 5000);
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== 1) return;
    clearTimeout(timeout);
    resolve(message);
  };
  socket.send(
    JSON.stringify({
      id: 1,
      method: 'Runtime.evaluate',
      params: { expression, returnByValue: true },
    }),
  );
});

socket.close();
if (response.result?.exceptionDetails) throw new Error(response.result.exceptionDetails.text);
console.log(JSON.stringify(response.result.result.value));
