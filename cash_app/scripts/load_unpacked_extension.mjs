const [, , extensionPath, portArg = '9223'] = process.argv;

if (!extensionPath) {
  throw new Error('Usage: node load_unpacked_extension.mjs <extension-path> [port]');
}

const versionResponse = await fetch(`http://127.0.0.1:${portArg}/json/version`);
if (!versionResponse.ok) {
  throw new Error(`Unable to inspect Chrome: HTTP ${versionResponse.status}`);
}

const { webSocketDebuggerUrl } = await versionResponse.json();
const socket = new WebSocket(webSocketDebuggerUrl);
const requestId = 1;

const result = await new Promise((resolve, reject) => {
  const timeout = setTimeout(
    () => reject(new Error('Timed out while loading the extension')),
    10_000,
  );

  socket.addEventListener('open', () => {
    socket.send(
      JSON.stringify({
        id: requestId,
        method: 'Extensions.loadUnpacked',
        params: { path: extensionPath },
      }),
    );
  });

  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    if (message.id !== requestId) return;

    clearTimeout(timeout);
    if (message.error) {
      reject(new Error(`${message.error.code}: ${message.error.message}`));
      return;
    }
    resolve(message.result);
  });

  socket.addEventListener('error', () => {
    clearTimeout(timeout);
    reject(new Error('Chrome DevTools WebSocket failed'));
  });
});

socket.close();
console.log(JSON.stringify(result));
