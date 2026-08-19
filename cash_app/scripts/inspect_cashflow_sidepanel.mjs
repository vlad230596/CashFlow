const [, , portArg = '9223', extensionId] = process.argv;
const targets = await (await fetch(`http://127.0.0.1:${portArg}/json/list`)).json();
const target = targets.find(
  (candidate) => candidate.type === 'page' &&
    candidate.url.startsWith('chrome-extension://') &&
    candidate.url.endsWith('/sidepanel.html') &&
    (!extensionId || candidate.url === `chrome-extension://${extensionId}/sidepanel.html`),
);
if (!target) throw new Error('CashFlow side panel target was not found');

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});
const response = await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('Inspection timed out')), 5000);
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== 1) return;
    clearTimeout(timeout);
    resolve(message);
  };
  socket.send(JSON.stringify({
    id: 1,
    method: 'Runtime.evaluate',
    params: {
      expression: `JSON.stringify({
        autoCollect: document.querySelector('.auto-toggle input')?.checked ?? null,
        busy: document.querySelector('.actions button:nth-child(2)')?.disabled ?? null,
        banks: Array.from(document.querySelectorAll('.bank'), (card) => ({
          bank: card.querySelector('h2')?.textContent,
          status: card.querySelector('.status')?.textContent?.trim(),
          summary: card.querySelector('.summary')?.textContent?.trim() ?? null,
          categories: card.querySelectorAll('.categories li').length,
        })),
      })`,
      returnByValue: true,
    },
  }));
});
socket.close();
if (response.result?.exceptionDetails) throw new Error(response.result.exceptionDetails.text);
console.log(response.result.result.value);
