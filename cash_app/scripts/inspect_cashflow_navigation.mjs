const [, , portArg = '9223', urlPrefix] = process.argv;
if (!urlPrefix) throw new Error('Usage: inspect_cashflow_navigation.mjs <port> <url-prefix>');

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

const expression = `JSON.stringify({
  url: location.href,
  title: document.title,
  monthlyControls: Array.from(document.querySelectorAll('button, [role="button"]'))
    .filter((element) => /повышенн|к[еэ]шб[еэ]к|категори/i.test(element.innerText || element.textContent || ''))
    .map((element) => ({
      tag: element.tagName,
      text: (element.innerText || element.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 500),
      html: element.outerHTML.slice(0, 5000),
      parentText: (element.parentElement?.innerText || '').trim().replace(/\s+/g, ' ').slice(0, 1000),
    })).slice(0, 30),
  links: Array.from(document.querySelectorAll('a[href]'), (element) => ({
    text: (element.innerText || element.getAttribute('aria-label') || '').trim().replace(/\\s+/g, ' ').slice(0, 160),
    href: element.href,
  })).filter((item) => item.text || /cash|bonus|loyal|category|benefit/i.test(item.href)).slice(0, 200),
  relevantControls: Array.from(document.querySelectorAll('button, [role="button"], [role="tab"], nav *'), (element) => ({
    tag: element.tagName,
    text: (element.innerText || element.getAttribute('aria-label') || '').trim().replace(/\\s+/g, ' ').slice(0, 160),
    ariaLabel: element.getAttribute('aria-label'),
    testId: element.getAttribute('data-test-id') || element.getAttribute('data-testid'),
  })).filter((item) => /к[еэ]шб|бонус|выгод|категор|cash|bonus|loyal|benefit/i.test(item.text + ' ' + (item.ariaLabel || '') + ' ' + (item.testId || ''))).slice(0, 100),
  relevantNodes: Array.from(document.querySelectorAll('[data-test-id], [data-testid]'), (element) => ({
    tag: element.tagName,
    testId: element.getAttribute('data-test-id') || element.getAttribute('data-testid'),
    text: (element.innerText || '').trim().replace(/\\s+/g, ' ').slice(0, 300),
  })).filter((item) => /к[еэ]шб|бонус|выгод|категор|cash|bonus|loyal|benefit|percent/i.test(item.text + ' ' + item.testId)).slice(0, 150),
  relevantResources: performance.getEntriesByType('resource').map((entry) => entry.name)
    .filter((url) => /cash|bonus|loyal|category|benefit/i.test(url)).slice(-100),
})`;

const response = await new Promise((resolve, reject) => {
  const id = 1;
  const timeout = setTimeout(() => reject(new Error('CDP evaluation timed out')), 10000);
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    clearTimeout(timeout);
    resolve(message);
  };
  socket.send(JSON.stringify({
    id,
    method: 'Runtime.evaluate',
    params: { expression, returnByValue: true },
  }));
});

socket.close();
if (response.result?.exceptionDetails) throw new Error(response.result.exceptionDetails.text);
console.log(response.result.result.value);
