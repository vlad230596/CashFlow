const [, , portArg = '9223', extensionId] = process.argv;
if (!extensionId) throw new Error('Usage: open_cashflow_sidepanel.mjs <port> <extension-id>');

const port = Number(portArg);
const extensionUrl = `chrome-extension://${extensionId}/sidepanel.html`;
let targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
const bootstrapTarget = await (
  await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(extensionUrl)}`, {
    method: 'PUT',
  })
).json();

const socket = new WebSocket(bootstrapTarget.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});

const response = await new Promise((resolve, reject) => {
  const id = 1;
  const timeout = setTimeout(() => reject(new Error('Opening side panel timed out')), 10000);
  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== id) return;
    clearTimeout(timeout);
    resolve(message);
  };
  socket.send(JSON.stringify({
    id,
    method: 'Runtime.evaluate',
    params: {
      expression: `(async () => {
        const currentWindow = await chrome.windows.getCurrent();
        await chrome.sidePanel.setOptions({ path: 'sidepanel.html', enabled: true });
        await chrome.sidePanel.open({ windowId: currentWindow.id });
        return { windowId: currentWindow.id };
      })()`,
      awaitPromise: true,
      returnByValue: true,
      userGesture: true,
    },
  }));
});

socket.close();
if (response.result?.exceptionDetails) {
  throw new Error(
    response.result.exceptionDetails.exception?.description ?? response.result.exceptionDetails.text,
  );
}

await new Promise((resolve) => setTimeout(resolve, 750));
targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
let extensionTargets = targets.filter((candidate) => candidate.url === extensionUrl);
if (extensionTargets.length > 1) {
  await fetch(`http://127.0.0.1:${port}/json/close/${bootstrapTarget.id}`);
  extensionTargets = extensionTargets.filter((candidate) => candidate.id !== bootstrapTarget.id);
}
console.log(JSON.stringify({
  bootstrapTargetId: bootstrapTarget.id,
  result: response.result.result.value,
  extensionTargets: extensionTargets
    .map((candidate) => ({ id: candidate.id, type: candidate.type, title: candidate.title })),
}));
