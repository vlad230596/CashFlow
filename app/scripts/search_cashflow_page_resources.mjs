const [, , portArg = '9223', urlPrefix, patternArg] = process.argv;
if (!urlPrefix || !patternArg) {
  throw new Error('Usage: search_cashflow_page_resources.mjs <port> <url-prefix> <pattern>');
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

const expression = `(async () => {
  const pattern = new RegExp(${JSON.stringify(patternArg)}, 'gi');
  const urls = [...new Set(
    performance.getEntriesByType('resource')
      .map((entry) => entry.name)
      .filter((url) => /\\.js(?:[?#]|$)/i.test(url)),
  )];
  const matches = [];
  for (const url of urls) {
    try {
      const source = await fetch(url).then((response) => response.text());
      const snippets = [];
      for (const match of source.matchAll(pattern)) {
        snippets.push(source.slice(Math.max(0, match.index - 180), match.index + match[0].length + 280));
        if (snippets.length === 8) break;
      }
      if (snippets.length) matches.push({ url, snippets });
    } catch (error) {
      // Cross-origin resources without CORS are expected and can be skipped.
    }
  }
  return matches;
})()`;

const response = await new Promise((resolve, reject) => {
  const id = 1;
  const timeout = setTimeout(() => reject(new Error('Resource search timed out')), 60000);
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    clearTimeout(timeout);
    resolve(message);
  };
  socket.send(JSON.stringify({
    id,
    method: 'Runtime.evaluate',
    params: { expression, awaitPromise: true, returnByValue: true },
  }));
});

socket.close();
if (response.result?.exceptionDetails) throw new Error(response.result.exceptionDetails.text);
console.log(JSON.stringify(response.result.result.value));
