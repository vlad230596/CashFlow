const [, , portArg = '9223', targetId] = process.argv;
if (!targetId) throw new Error('Usage: reload_cashflow_page.mjs <port> <target-id>');

const targets = await (await fetch(`http://127.0.0.1:${Number(portArg)}/json`)).json();
const target = targets.find((candidate) => candidate.type === 'page' && candidate.id === targetId);
if (!target) throw new Error(`Page target not found: ${targetId}`);

const socket = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});
await new Promise((resolve, reject) => {
  const timeout = setTimeout(() => reject(new Error('CDP reload timed out')), 5000);
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== 1) return;
    clearTimeout(timeout);
    resolve(message);
  };
  socket.send(JSON.stringify({ id: 1, method: 'Page.reload', params: {} }));
});
socket.close();
console.log(JSON.stringify({ reloaded: true, targetId }));
